/**
 * Ensures a Stripe Customer exists for the Supabase user and is stored on profiles.
 */
import { createClient, type SupabaseClient, type User } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { supabaseClientKey } from "./clientApiKey.ts";

export function createAdminClient(): SupabaseClient {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    throw new Error("Missing Supabase env");
  }
  return createClient(supabaseUrl, serviceKey);
}

export async function requireUser(req: Request): Promise<User> {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    throw new Error("Unauthorized");
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const clientKey = supabaseClientKey();
  if (!supabaseUrl || !clientKey) {
    throw new Error("Missing Supabase env");
  }

  const token = authHeader.replace("Bearer ", "");
  const client = createClient(supabaseUrl, clientKey);
  const { data, error } = await client.auth.getUser(token);
  if (error || !data.user) {
    throw new Error("Unauthorized");
  }
  return data.user;
}

export async function ensureProfileForUser(
  admin: SupabaseClient,
  user: User,
): Promise<void> {
  const fullName =
    typeof user.user_metadata?.full_name === "string"
      ? String(user.user_metadata.full_name).trim()
      : typeof user.email === "string"
      ? user.email.split("@")[0] ?? ""
      : "";

  const existing = await admin
    .from("profiles")
    .select("id")
    .eq("id", user.id)
    .maybeSingle();

  if (existing.data) {
    if (fullName) {
      await admin
        .from("profiles")
        .update({ full_name: fullName })
        .eq("id", user.id);
    }
    return;
  }

  const inserted = await admin.from("profiles").insert({
    id: user.id,
    full_name: fullName || null,
    role: "customer",
  });
  if (inserted.error) {
    throw new Error(inserted.error.message);
  }
}

export async function ensureStripeCustomer(
  admin: SupabaseClient,
  stripeKey: string,
  user: User,
): Promise<string> {
  await ensureProfileForUser(admin, user);

  const { data: profile, error } = await admin
    .from("profiles")
    .select("id, stripe_customer_id, full_name")
    .eq("id", user.id)
    .maybeSingle();

  if (error) {
    throw new Error(error.message);
  }

  const existing =
    typeof profile?.stripe_customer_id === "string"
      ? profile.stripe_customer_id.trim()
      : "";
  if (existing.startsWith("cus_")) {
    return existing;
  }

  const params = new URLSearchParams({
    "metadata[supabase_user_id]": user.id,
  });
  if (typeof user.email === "string" && user.email.trim()) {
    params.set("email", user.email.trim().toLowerCase());
  }
  const fullName =
    (typeof profile?.full_name === "string" && profile.full_name.trim()) ||
    (typeof user.user_metadata?.full_name === "string"
      ? String(user.user_metadata.full_name).trim()
      : "");
  if (fullName) {
    params.set("name", fullName.slice(0, 200));
  }

  const stripeRes = await fetch("https://api.stripe.com/v1/customers", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${stripeKey}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: params,
  });
  const stripeJson = await stripeRes.json();
  if (!stripeRes.ok || typeof stripeJson?.id !== "string") {
    throw new Error(
      typeof stripeJson?.error?.message === "string"
        ? stripeJson.error.message
        : "Could not create Stripe customer",
    );
  }

  const customerId = stripeJson.id as string;
  const { error: updateError } = await admin
    .from("profiles")
    .update({ stripe_customer_id: customerId })
    .eq("id", user.id);

  if (updateError) {
    throw new Error(updateError.message);
  }

  return customerId;
}
