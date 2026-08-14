// Registers FCM (+ optional APNs) device tokens for a customer.
// POST { customer_email, fcm_token, apns_token?, platform?, customer_id? }
// Auth: apikey (sb_publishable_…). verify_jwt = false.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { requireClientApiKey } from "../_shared/clientApiKey.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return Response.json(
      { error: "Method not allowed" },
      { status: 405, headers: CORS_HEADERS },
    );
  }

  const unauthorized = requireClientApiKey(req, CORS_HEADERS);
  if (unauthorized) return unauthorized;

  try {
    const body = await req.json();
    const email = normalizeEmail(body?.customer_email);
    const token = typeof body?.fcm_token === "string" ? body.fcm_token.trim() : "";
    const apnsTokenRaw =
      typeof body?.apns_token === "string" ? body.apns_token.trim() : "";
    const apnsToken =
      apnsTokenRaw.length >= 32
        ? apnsTokenRaw.replace(/\s+/g, "").toLowerCase()
        : null;
    const platform =
      typeof body?.platform === "string" && body.platform.trim()
        ? body.platform.trim().toLowerCase()
        : "ios";
    const customerIdHint = asUUID(body?.customer_id);

    if (!email.includes("@") || email.endsWith("@chercharge.local")) {
      return Response.json(
        { error: "customer_email must be a real account email" },
        { status: 400, headers: CORS_HEADERS },
      );
    }
    if (token.length < 20) {
      return Response.json(
        { error: "fcm_token is required" },
        { status: 400, headers: CORS_HEADERS },
      );
    }

    const admin = createAdminClient();
    let customerId = customerIdHint;

    if (!customerId) {
      const user = await findCustomerByEmail(admin, email);
      customerId = user?.id ?? null;
    }

    const row: Record<string, unknown> = {
      customer_id: customerId,
      customer_email: email,
      fcm_token: token,
      platform,
      updated_at: new Date().toISOString(),
    };
    if (apnsToken) {
      row.apns_token = apnsToken;
    }

    const { data, error } = await admin.from("device_tokens").upsert(
      row,
      { onConflict: "fcm_token" },
    ).select(
      "id, customer_id, customer_email, platform, apns_token, updated_at",
    ).maybeSingle();

    if (error) {
      return Response.json(
        { error: error.message },
        { status: 400, headers: CORS_HEADERS },
      );
    }

    return Response.json(
      { ok: true, token: data },
      { headers: CORS_HEADERS },
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return Response.json(
      { error: message },
      { status: 500, headers: CORS_HEADERS },
    );
  }
});

function createAdminClient() {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  }
  return createClient(supabaseUrl, serviceKey);
}

async function findCustomerByEmail(
  admin: ReturnType<typeof createClient>,
  email: string,
) {
  for (let page = 1; page <= 25; page++) {
    const listed = await admin.auth.admin.listUsers({ page, perPage: 200 });
    if (listed.error) throw new Error(listed.error.message);
    const found = listed.data.users.find(
      (u) => (u.email ?? "").toLowerCase() === email,
    );
    if (found) return found;
    if (listed.data.users.length < 200) break;
  }
  return null;
}

function normalizeEmail(value: unknown): string {
  if (typeof value !== "string") return "";
  return value.trim().toLowerCase();
}

function asUUID(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(trimmed)
    ? trimmed
    : null;
}
