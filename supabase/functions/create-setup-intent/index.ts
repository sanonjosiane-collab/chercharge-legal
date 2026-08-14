// Creates a Stripe SetupIntent so the customer can save a card without charging.
// Requires Supabase Auth JWT.
// Returns { clientSecret, setupIntentId, customerId }

import {
  createAdminClient,
  ensureStripeCustomer,
  requireUser,
} from "../_shared/stripeCustomer.ts";
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

    const admin = createAdminClient();
    const customerId = await ensureStripeCustomer(admin, stripeKey, user);

    const params = new URLSearchParams({
      customer: customerId,
      usage: "off_session",
      "automatic_payment_methods[enabled]": "true",
      "metadata[supabase_user_id]": user.id,
      "metadata[flow]": "save_payment_method",
    });

    const stripeRes = await fetch("https://api.stripe.com/v1/setup_intents", {
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
        "Stripe SetupIntent creation failed",
      );
      return Response.json(
        { error: message },
        { status: stripeRes.status, headers: CORS_HEADERS },
      );
    }

    const clientSecret = stripeJson.client_secret;
    const setupIntentId = stripeJson.id;
    if (
      typeof clientSecret !== "string" ||
      !clientSecret.startsWith("seti_") ||
      !clientSecret.includes("_secret_") ||
      typeof setupIntentId !== "string"
    ) {
      return Response.json(
        { error: "Payment server returned an invalid setup secret." },
        { status: 500, headers: CORS_HEADERS },
      );
    }

    return Response.json(
      {
        clientSecret,
        setupIntentId,
        customerId,
      },
      { headers: CORS_HEADERS },
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    const status = message === "Unauthorized" ? 401 : 500;
    return Response.json({ error: message }, { status, headers: CORS_HEADERS });
  }
});
