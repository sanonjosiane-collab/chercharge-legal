// Stripe webhook (live or test). Completes founding pre-orders when PaymentIntents succeed.
// Configure in Stripe Dashboard → Developers → Webhooks:
//   URL: https://<PROJECT_REF>.supabase.co/functions/v1/stripe-webhook
//   Events: payment_intent.succeeded
// Secrets: STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET (whsec_… from the endpoint)
// verify_jwt must be false — Stripe signs requests; there is no Supabase JWT.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { stripeSecretKey } from "../_shared/stripeSecret.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, stripe-signature",
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

  const webhookSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET")?.trim();
  if (!webhookSecret) {
    return Response.json(
      { error: "Missing STRIPE_WEBHOOK_SECRET" },
      { status: 500, headers: CORS_HEADERS },
    );
  }

  if (!stripeSecretKey()) {
    return Response.json(
      { error: "Missing STRIPE_SECRET_KEY" },
      { status: 500, headers: CORS_HEADERS },
    );
  }

  const signature = req.headers.get("stripe-signature");
  if (!signature) {
    return Response.json(
      { error: "Missing stripe-signature" },
      { status: 400, headers: CORS_HEADERS },
    );
  }

  const payload = await req.text();
  let event: StripeEvent;
  try {
    event = await verifyStripeSignature(payload, signature, webhookSecret);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Invalid signature";
    return Response.json({ error: message }, { status: 400, headers: CORS_HEADERS });
  }

  try {
    if (event.type === "payment_intent.succeeded") {
      const pi = event.data?.object as PaymentIntentObject | undefined;
      if (pi?.id && pi.metadata?.flow === "preorder") {
        const userId = pi.metadata.user_id;
        if (typeof userId === "string" && userId.length > 0) {
          const admin = createAdminClient();
          const { error } = await admin.rpc("complete_preorder", {
            p_payment_intent_id: pi.id,
            p_user_id: userId,
          });
          // Idempotent: already-completed is fine; missing row is logged but 200 so Stripe stops retrying forever for book-a-charge PIs mis-tagged.
          if (error && !/already|not pending|not found/i.test(error.message)) {
            console.error("complete_preorder failed", error.message);
            return Response.json(
              { error: error.message },
              { status: 500, headers: CORS_HEADERS },
            );
          }
        }
      }
    }

    return Response.json({ received: true }, { headers: CORS_HEADERS });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return Response.json({ error: message }, { status: 500, headers: CORS_HEADERS });
  }
});

type StripeEvent = {
  type: string;
  data?: { object?: unknown };
};

type PaymentIntentObject = {
  id?: string;
  metadata?: Record<string, string>;
};

function createAdminClient() {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    throw new Error("Missing Supabase env");
  }
  return createClient(supabaseUrl, serviceKey);
}

async function verifyStripeSignature(
  payload: string,
  header: string,
  secret: string,
): Promise<StripeEvent> {
  const parts = Object.fromEntries(
    header.split(",").map((piece) => {
      const [k, ...rest] = piece.split("=");
      return [k.trim(), rest.join("=").trim()];
    }),
  );

  const timestamp = parts["t"];
  const v1 = parts["v1"];
  if (!timestamp || !v1) {
    throw new Error("Malformed stripe-signature header");
  }

  const ageSeconds = Math.abs(Date.now() / 1000 - Number(timestamp));
  if (!Number.isFinite(ageSeconds) || ageSeconds > 300) {
    throw new Error("Stripe signature timestamp outside tolerance");
  }

  const signedPayload = `${timestamp}.${payload}`;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(signedPayload),
  );
  const expected = [...new Uint8Array(mac)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  if (!timingSafeEqualHex(expected, v1)) {
    throw new Error("Stripe signature mismatch");
  }

  return JSON.parse(payload) as StripeEvent;
}

function timingSafeEqualHex(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}
