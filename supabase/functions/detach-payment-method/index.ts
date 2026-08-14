// Detaches a saved Stripe PaymentMethod from the authenticated customer.
// POST { "payment_method_id": "pm_..." }
// Requires Supabase Auth JWT.

import {
  createAdminClient,
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
    const body = await req.json().catch(() => ({}));
    const paymentMethodId =
      typeof body?.payment_method_id === "string"
        ? body.payment_method_id.trim()
        : "";

    if (!paymentMethodId.startsWith("pm_")) {
      return Response.json(
        { error: "payment_method_id is required" },
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

    const admin = createAdminClient();
    const { data: profile } = await admin
      .from("profiles")
      .select("stripe_customer_id")
      .eq("id", user.id)
      .maybeSingle();

    const customerId =
      typeof profile?.stripe_customer_id === "string"
        ? profile.stripe_customer_id.trim()
        : "";
    if (!customerId.startsWith("cus_")) {
      return Response.json(
        { error: "No saved cards on this account." },
        { status: 404, headers: CORS_HEADERS },
      );
    }

    const getRes = await fetch(
      `https://api.stripe.com/v1/payment_methods/${encodeURIComponent(paymentMethodId)}`,
      { headers: { Authorization: `Bearer ${stripeKey}` } },
    );
    const getJson = await getRes.json();
    if (!getRes.ok) {
      const message = safeStripeErrorMessage(
        typeof getJson?.error?.message === "string"
          ? getJson.error.message
          : undefined,
        "Could not find that card",
      );
      return Response.json(
        { error: message },
        { status: getRes.status, headers: CORS_HEADERS },
      );
    }

    const owner =
      typeof getJson?.customer === "string" ? getJson.customer : null;
    if (owner !== customerId) {
      return Response.json(
        { error: "That card does not belong to this account." },
        { status: 403, headers: CORS_HEADERS },
      );
    }

    const detachRes = await fetch(
      `https://api.stripe.com/v1/payment_methods/${encodeURIComponent(paymentMethodId)}/detach`,
      {
        method: "POST",
        headers: { Authorization: `Bearer ${stripeKey}` },
      },
    );
    const detachJson = await detachRes.json();
    if (!detachRes.ok) {
      const message = safeStripeErrorMessage(
        typeof detachJson?.error?.message === "string"
          ? detachJson.error.message
          : undefined,
        "Could not remove that card",
      );
      return Response.json(
        { error: message },
        { status: detachRes.status, headers: CORS_HEADERS },
      );
    }

    return Response.json({ ok: true }, { headers: CORS_HEADERS });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    const status = message === "Unauthorized" ? 401 : 500;
    return Response.json({ error: message }, { status, headers: CORS_HEADERS });
  }
});
