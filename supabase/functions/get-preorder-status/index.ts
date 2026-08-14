// Returns pre-order pricing, slot availability, and the caller's preorder/credit status.
// Requires Supabase Auth JWT.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { supabaseClientKey } from "../_shared/clientApiKey.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const CAMPAIGN_ID = "early_bird_50";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  if (req.method !== "POST" && req.method !== "GET") {
    return Response.json(
      { error: "Method not allowed" },
      { status: 405, headers: CORS_HEADERS },
    );
  }

  try {
    const user = await requireUser(req);
    const admin = createAdminClient();
    await ensureProfile(admin, user);

    const { data, error } = await admin.rpc("get_preorder_quote", {
      p_campaign_id: CAMPAIGN_ID,
      p_user_id: user.id,
    });

    if (error) {
      return Response.json(
        { error: error.message },
        { status: 400, headers: CORS_HEADERS },
      );
    }

    const row = Array.isArray(data) ? data[0] : data;
    if (!row) {
      return Response.json(
        { error: "Could not load preorder quote" },
        { status: 500, headers: CORS_HEADERS },
      );
    }

    return Response.json(
      {
        campaignId: CAMPAIGN_ID,
        priceCents: row.price_cents,
        promoApplied: row.promo_applied,
        slotsRemaining: row.slots_remaining,
        maxSlots: row.max_slots,
        standardPriceCents: row.standard_price_cents,
        discountCents: row.discount_cents,
        alreadyPreordered: row.already_preordered,
        existingStatus: row.existing_status,
        accountCreditCents: row.account_credit_cents,
        preorderCreditConsumed: row.preorder_credit_consumed,
        tier: row.tier ?? null,
      },
      { headers: CORS_HEADERS },
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    const status = message === "Unauthorized" ? 401 : 500;
    return Response.json({ error: message }, { status, headers: CORS_HEADERS });
  }
});

function createAdminClient() {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    throw new Error("Missing Supabase env");
  }
  return createClient(supabaseUrl, serviceKey);
}

async function requireUser(req: Request) {
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

async function ensureProfile(
  admin: ReturnType<typeof createClient>,
  user: { id: string; email?: string | null; user_metadata?: Record<string, unknown> },
) {
  const metaName = user.user_metadata?.full_name;
  const fullName =
    typeof metaName === "string" && metaName.trim()
      ? metaName.trim()
      : (user.email?.split("@")[0] ?? "Customer");

  const existing = await admin
    .from("profiles")
    .select("id")
    .eq("id", user.id)
    .maybeSingle();

  if (existing.data) return;

  const inserted = await admin.from("profiles").insert({
    id: user.id,
    full_name: fullName,
    role: "customer",
  });
  if (inserted.error) {
    throw new Error(inserted.error.message);
  }
}
