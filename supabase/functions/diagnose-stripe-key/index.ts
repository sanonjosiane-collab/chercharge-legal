// Temporary diagnostics for STRIPE_SECRET_KEY — does not return the secret value.
// POST with apikey. Safe checks: length, account marker, Stripe /v1/balance.

import { requireClientApiKey } from "../_shared/clientApiKey.ts";
import {
  normalizeStripeSecret,
  stripeSecretKey,
} from "../_shared/stripeSecret.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

/** Must match the live publishable key account in iOS Secrets.plist */
const EXPECTED_ACCOUNT_MARKER = "51SKXRc";

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

  const raw = Deno.env.get("STRIPE_SECRET_KEY") ?? "";
  const key = stripeSecretKey() ?? "";
  const normalized = normalizeStripeSecret(raw);

  const report: Record<string, unknown> = {
    present: raw.length > 0,
    rawLength: raw.length,
    normalizedLength: normalized.length,
    startsWithSkLive: normalized.startsWith("sk_live_"),
    startsWithSkTest: normalized.startsWith("sk_test_"),
    hadWrappingQuotes:
      (raw.trim().startsWith('"') && raw.trim().endsWith('"')) ||
      (raw.trim().startsWith("'") && raw.trim().endsWith("'")),
    hadInternalWhitespace: /\s/.test(raw.trim()),
    accountMarkerMatch: normalized.startsWith(
      `sk_live_${EXPECTED_ACCOUNT_MARKER}`,
    ),
    expectedAccountMarker: EXPECTED_ACCOUNT_MARKER,
    // First 15 chars only — enough to confirm sk_live_51SKXRc, not the secret body.
    prefix15: normalized.slice(0, 15),
  };

  if (!key) {
    return Response.json(
      { ...report, stripeBalance: "missing_key" },
      { headers: CORS_HEADERS },
    );
  }

  try {
    const stripeRes = await fetch("https://api.stripe.com/v1/balance", {
      headers: { Authorization: `Bearer ${key}` },
    });
    const stripeJson = await stripeRes.json();
    report.stripeHttpStatus = stripeRes.status;
    report.stripeBalanceOk = stripeRes.ok;
    if (!stripeRes.ok) {
      const msg =
        typeof stripeJson?.error?.message === "string"
          ? stripeJson.error.message
          : "stripe_error";
      report.stripeErrorClass = /invalid api key/i.test(msg)
        ? "invalid_api_key"
        : "other";
    }
  } catch {
    report.stripeBalanceOk = false;
    report.stripeErrorClass = "network";
  }

  return Response.json(report, { headers: CORS_HEADERS });
});
