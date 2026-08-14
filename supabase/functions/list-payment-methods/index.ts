// Lists card payment methods for the authenticated customer's Stripe Customer.
// Requires Supabase Auth JWT.
// Returns { paymentMethods: [{ id, brand, last4, expMonth, expYear }] }

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

  if (req.method !== "POST" && req.method !== "GET") {
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
    const { data: profile } = await admin
      .from("profiles")
      .select("stripe_customer_id")
      .eq("id", user.id)
      .maybeSingle();

    let customerId =
      typeof profile?.stripe_customer_id === "string"
        ? profile.stripe_customer_id.trim()
        : "";

    // No customer yet → nothing saved.
    if (!customerId.startsWith("cus_")) {
      return Response.json({ paymentMethods: [] }, { headers: CORS_HEADERS });
    }

    // Refresh/ensure in case the stored id is stale; ignore create if already set.
    customerId = await ensureStripeCustomer(admin, stripeKey, user);

    const stripeRes = await fetch(
      `https://api.stripe.com/v1/payment_methods?customer=${encodeURIComponent(customerId)}&type=card&limit=20`,
      { headers: { Authorization: `Bearer ${stripeKey}` } },
    );
    const stripeJson = await stripeRes.json();
    if (!stripeRes.ok) {
      const message = safeStripeErrorMessage(
        typeof stripeJson?.error?.message === "string"
          ? stripeJson.error.message
          : undefined,
        "Could not load saved cards",
      );
      return Response.json(
        { error: message },
        { status: stripeRes.status, headers: CORS_HEADERS },
      );
    }

    const data = Array.isArray(stripeJson?.data) ? stripeJson.data : [];
    const paymentMethods = data
      .map((pm: Record<string, unknown>) => {
        const id = typeof pm.id === "string" ? pm.id : "";
        const card = (pm.card ?? {}) as Record<string, unknown>;
        const brand = typeof card.brand === "string" ? card.brand : "card";
        const last4 = typeof card.last4 === "string" ? card.last4 : "";
        const expMonth =
          typeof card.exp_month === "number" ? card.exp_month : null;
        const expYear =
          typeof card.exp_year === "number" ? card.exp_year : null;
        if (!id.startsWith("pm_") || !last4) return null;
        return { id, brand, last4, expMonth, expYear };
      })
      .filter(Boolean);

    return Response.json({ paymentMethods }, { headers: CORS_HEADERS });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    const status = message === "Unauthorized" ? 401 : 500;
    return Response.json({ error: message }, { status, headers: CORS_HEADERS });
  }
});
