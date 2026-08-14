// Verifies a succeeded Stripe PaymentIntent and grants pre-order credit.
// POST { "payment_intent_id": "pi_..." } — requires Supabase Auth JWT.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { supabaseClientKey } from "../_shared/clientApiKey.ts";
import {
  assertUsableStripeSecret,
  safeStripeErrorMessage,
  stripeSecretKey,
} from "../_shared/stripeSecret.ts";

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

  try {
    const user = await requireUser(req);
    const body = await req.json();
    const paymentIntentId = body?.payment_intent_id;

    if (typeof paymentIntentId !== "string" || !paymentIntentId.startsWith("pi_")) {
      return Response.json(
        { error: "payment_intent_id required" },
        { status: 400, headers: CORS_HEADERS },
      );
    }

    const stripeKey = stripeSecretKey();
    if (!stripeKey) {
      return Response.json(
        { error: "Missing STRIPE_SECRET_KEY" },
        { status: 500, headers: CORS_HEADERS },
      );
    }
    const secretCheck = assertUsableStripeSecret(stripeKey);
    if (!secretCheck.ok) {
      return Response.json(
        { error: secretCheck.error },
        { status: 500, headers: CORS_HEADERS },
      );
    }

    const stripeRes = await fetch(
      `https://api.stripe.com/v1/payment_intents/${paymentIntentId}`,
      {
        headers: { Authorization: `Bearer ${stripeKey}` },
      },
    );

    const stripeJson = await stripeRes.json();
    if (!stripeRes.ok) {
      const message = safeStripeErrorMessage(
        typeof stripeJson?.error?.message === "string"
          ? stripeJson.error.message
          : undefined,
        "Could not verify payment",
      );
      return Response.json(
        { error: message },
        { status: stripeRes.status, headers: CORS_HEADERS },
      );
    }

    if (stripeJson.status !== "succeeded") {
      return Response.json(
        { error: "Payment has not succeeded yet." },
        { status: 409, headers: CORS_HEADERS },
      );
    }

    const metadataUserId = stripeJson.metadata?.user_id;
    if (metadataUserId && metadataUserId !== user.id) {
      return Response.json(
        { error: "Payment does not belong to this account." },
        { status: 403, headers: CORS_HEADERS },
      );
    }

    const admin = createAdminClient();
    const { data, error } = await admin.rpc("complete_preorder", {
      p_payment_intent_id: paymentIntentId,
      p_user_id: user.id,
    });

    if (error) {
      return Response.json(
        { error: error.message },
        { status: 400, headers: CORS_HEADERS },
      );
    }

    const row = Array.isArray(data) ? data[0] : data;

    return Response.json(
      {
        preorderId: row?.preorder_id,
        creditCents: row?.credit_cents,
        promoApplied: row?.promo_applied,
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
