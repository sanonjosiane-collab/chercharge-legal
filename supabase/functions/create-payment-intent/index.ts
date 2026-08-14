// Creates a Stripe PaymentIntent for Book a Charge (live mode via STRIPE_SECRET_KEY=sk_live_…).
// POST { "amount_cents": 4999, "currency": "usd", "metadata": { "job_label": "..." } }
// Returns { "clientSecret": "...", "paymentIntentId": "pi_..." } — never returns the secret key.
// Auth: apikey header (sb_publishable_… or legacy anon). verify_jwt is off for new keys.

import { requireClientApiKey } from "../_shared/clientApiKey.ts";
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

const MAX_AMOUNT_CENTS = 50_000; // $500.00

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

    const body = await req.json();
    const amountCents = body?.amount_cents;
    const currency =
      typeof body?.currency === "string" && body.currency.length === 3
        ? body.currency.toLowerCase()
        : "usd";

    if (
      typeof amountCents !== "number" ||
      !Number.isInteger(amountCents) ||
      amountCents < 50 ||
      amountCents > MAX_AMOUNT_CENTS
    ) {
      return Response.json(
        {
          error:
            "amount_cents must be an integer between 50 and 50000 (cents)",
        },
        { status: 400, headers: CORS_HEADERS },
      );
    }

    const params = new URLSearchParams({
      amount: String(amountCents),
      currency,
      "automatic_payment_methods[enabled]": "true",
    });

    const metadata = body?.metadata;
    if (metadata && typeof metadata === "object") {
      for (const [key, value] of Object.entries(metadata)) {
        if (typeof value === "string" && value.length > 0) {
          params.set(`metadata[${key}]`, value.slice(0, 500));
        }
      }
    }

    const stripeRes = await fetch("https://api.stripe.com/v1/payment_intents", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${stripeKey}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: params,
    });

    const stripeJson = await stripeRes.json();
    if (!stripeRes.ok) {
      const message = safeStripeErrorMessage(
        typeof stripeJson?.error?.message === "string"
          ? stripeJson.error.message
          : undefined,
        "Stripe PaymentIntent creation failed",
      );
      return Response.json(
        { error: message },
        { status: stripeRes.status, headers: CORS_HEADERS },
      );
    }

    return Response.json(
      {
        clientSecret: stripeJson.client_secret,
        paymentIntentId: stripeJson.id,
      },
      { headers: CORS_HEADERS },
    );
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : "Unknown error" },
      { status: 500, headers: CORS_HEADERS },
    );
  }
});
