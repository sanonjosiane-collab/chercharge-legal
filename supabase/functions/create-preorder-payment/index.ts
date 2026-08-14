// Creates a Stripe PaymentIntent for a pre-launch pre-order.
// Server computes price and reserves a promo slot atomically.
// Resumes pending checkouts; reuses failed/cancelled rows (unique campaign+user).
// POST {
//   "agreement_accepted": true,
//   "terms_version": "founding-access-v1",
//   "agreement_accepted_at": "ISO-8601" (optional; server stamps if omitted)
// }
// Requires Supabase Auth JWT.

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

const CAMPAIGN_ID = "early_bird_50";
/** Keep in sync with iOS PreOrderService.foundingTermsVersion */
const CURRENT_TERMS_VERSION = "founding-access-v1";
const STALE_PENDING_MINUTES = 30;

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
    const admin = createAdminClient();
    await ensureProfile(admin, user);
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

    // Free abandoned checkouts so they cannot lock founding inventory forever.
    const { data: staleIds } = await admin.rpc(
      "cancel_stale_preorder_reservations",
      {
        p_campaign_id: CAMPAIGN_ID,
        p_max_age_minutes: STALE_PENDING_MINUTES,
      },
    );
    if (Array.isArray(staleIds)) {
      for (const row of staleIds) {
        const pi =
          typeof row === "string"
            ? row
            : row?.stripe_payment_intent_id;
        if (typeof pi === "string" && pi.startsWith("pi_")) {
          await fetch(`https://api.stripe.com/v1/payment_intents/${pi}/cancel`, {
            method: "POST",
            headers: { Authorization: `Bearer ${stripeKey}` },
          }).catch(() => null);
        }
      }
    }

    const agreementAccepted = body?.agreement_accepted === true;
    const termsVersion =
      typeof body?.terms_version === "string" ? body.terms_version.trim() : "";
    if (!agreementAccepted) {
      return Response.json(
        { error: "You must accept the Founding Access agreement before paying." },
        { status: 400, headers: CORS_HEADERS },
      );
    }
    if (termsVersion !== CURRENT_TERMS_VERSION) {
      return Response.json(
        { error: "Please refresh the app and accept the current Founding Access terms." },
        { status: 400, headers: CORS_HEADERS },
      );
    }

    const agreementAcceptedAt =
      typeof body?.agreement_accepted_at === "string" &&
        !Number.isNaN(Date.parse(body.agreement_accepted_at))
        ? new Date(body.agreement_accepted_at).toISOString()
        : new Date().toISOString();

    const { data: quoteRows, error: quoteError } = await admin.rpc(
      "get_preorder_quote",
      {
        p_campaign_id: CAMPAIGN_ID,
        p_user_id: user.id,
      },
    );

    if (quoteError) {
      return Response.json(
        { error: quoteError.message },
        { status: 400, headers: CORS_HEADERS },
      );
    }

    const quote = Array.isArray(quoteRows) ? quoteRows[0] : quoteRows;
    if (!quote) {
      return Response.json(
        { error: "Could not load preorder quote" },
        { status: 500, headers: CORS_HEADERS },
      );
    }

    const existingStatus = String(
      quote.existing_status ?? quote.existingStatus ?? "",
    );
    const alreadyPreordered = Boolean(
      quote.already_preordered ?? quote.alreadyPreordered,
    );

    if (existingStatus === "completed") {
      return Response.json(
        { error: "You already completed your pre-order." },
        { status: 409, headers: CORS_HEADERS },
      );
    }

    // Load any existing row for this user+campaign (pending / failed / cancelled).
    const { data: existingRow } = await admin
      .from("preorders")
      .select(
        "id, status, stripe_payment_intent_id, amount_cents, promo_applied, tier",
      )
      .eq("campaign_id", CAMPAIGN_ID)
      .eq("user_id", user.id)
      .maybeSingle();

    // Resume a still-open pending PaymentIntent when possible.
    if (
      (existingStatus === "pending" || existingRow?.status === "pending") &&
      existingRow?.stripe_payment_intent_id
    ) {
      const resume = await tryResumePaymentIntent(
        stripeKey,
        existingRow.stripe_payment_intent_id,
      );
      if (resume) {
        await admin
          .from("preorders")
          .update({
            agreement_accepted_at: agreementAcceptedAt,
            terms_version: termsVersion,
          })
          .eq("id", existingRow.id);

        return Response.json(
          {
            clientSecret: resume.clientSecret,
            paymentIntentId: existingRow.stripe_payment_intent_id,
            priceCents: existingRow.amount_cents,
            promoApplied: existingRow.promo_applied,
            tier: existingRow.tier ?? quote.tier ?? null,
            slotsRemaining: quote.slots_remaining ?? quote.slotsRemaining,
            resumed: true,
          },
          { headers: CORS_HEADERS },
        );
      }

      // Dead pending PI — cancel remotely and create a fresh one below.
      await fetch(
        `https://api.stripe.com/v1/payment_intents/${existingRow.stripe_payment_intent_id}/cancel`,
        {
          method: "POST",
          headers: { Authorization: `Bearer ${stripeKey}` },
        },
      ).catch(() => null);
    }

    const priceCents = Number(quote.price_cents ?? quote.priceCents);
    const promoApplied = Boolean(quote.promo_applied ?? quote.promoApplied);
    const tier = String(quote.tier ?? "standard");

    if (!Number.isFinite(priceCents) || priceCents <= 0) {
      return Response.json(
        { error: "Invalid preorder price from server." },
        { status: 500, headers: CORS_HEADERS },
      );
    }

    const params = new URLSearchParams({
      amount: String(priceCents),
      currency: "usd",
      "automatic_payment_methods[enabled]": "true",
      "metadata[campaign_id]": CAMPAIGN_ID,
      "metadata[user_id]": user.id,
      "metadata[flow]": "preorder",
      "metadata[promo_applied]": promoApplied ? "true" : "false",
      "metadata[tier]": tier,
      "metadata[terms_version]": termsVersion,
    });

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

    const paymentIntentId = stripeJson.id as string;

    const { error: reserveError } = await admin.rpc("reserve_preorder_slot", {
      p_campaign_id: CAMPAIGN_ID,
      p_user_id: user.id,
      p_amount_cents: priceCents,
      p_promo_applied: promoApplied,
      p_payment_intent_id: paymentIntentId,
      p_tier: tier,
      p_agreement_accepted_at: agreementAcceptedAt,
      p_terms_version: termsVersion,
    });

    if (reserveError) {
      await fetch(`https://api.stripe.com/v1/payment_intents/${paymentIntentId}/cancel`, {
        method: "POST",
        headers: { Authorization: `Bearer ${stripeKey}` },
      }).catch(() => null);

      // Friendlier message for the old unique-constraint failure mode.
      const raw = reserveError.message || "";
      const message = raw.includes("preorders_campaign_id_user_id_key")
        ? "A previous Founding Access checkout is still on file. Tap Accept & pay again to resume it."
        : raw;

      return Response.json(
        { error: message },
        { status: 409, headers: CORS_HEADERS },
      );
    }

    return Response.json(
      {
        clientSecret: stripeJson.client_secret,
        paymentIntentId,
        priceCents,
        promoApplied,
        tier,
        slotsRemaining: Math.max(
          0,
          Number(quote.slots_remaining ?? quote.slotsRemaining ?? 1) - 1,
        ),
        resumed: Boolean(existingRow) || alreadyPreordered,
      },
      { headers: CORS_HEADERS },
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    const status = message === "Unauthorized" ? 401 : 500;
    return Response.json({ error: message }, { status, headers: CORS_HEADERS });
  }
});

async function tryResumePaymentIntent(
  stripeKey: string,
  paymentIntentId: string,
): Promise<{ clientSecret: string } | null> {
  const resumeRes = await fetch(
    `https://api.stripe.com/v1/payment_intents/${paymentIntentId}`,
    { headers: { Authorization: `Bearer ${stripeKey}` } },
  );
  const resumeJson = await resumeRes.json();
  if (!resumeRes.ok || !resumeJson?.client_secret) return null;

  const status = String(resumeJson.status || "");
  // Only resume intents that can still accept payment.
  if (
    status === "requires_payment_method" ||
    status === "requires_confirmation" ||
    status === "requires_action"
  ) {
    return { clientSecret: resumeJson.client_secret as string };
  }
  return null;
}

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
