/** Server-only Stripe secret key from Supabase Edge secrets. Never ship to the client. */

/** Normalize secrets mangled by shell quoting / copy-paste. Never log the value. */
export function normalizeStripeSecret(raw: string | undefined | null): string {
  let key = (raw ?? "").trim();
  // Strip wrapping quotes from `secrets set KEY="sk_live_…"` mishaps.
  if (
    (key.startsWith('"') && key.endsWith('"')) ||
    (key.startsWith("'") && key.endsWith("'"))
  ) {
    key = key.slice(1, -1).trim();
  }
  // Remove accidental whitespace / newlines inside the paste.
  key = key.replace(/\s+/g, "");
  return key;
}

export function stripeSecretKey(): string | null {
  const key = normalizeStripeSecret(Deno.env.get("STRIPE_SECRET_KEY"));
  if (!key) return null;
  return key;
}

/** True when the configured secret is a live-mode key. */
export function isStripeLiveSecret(key: string): boolean {
  return key.startsWith("sk_live_");
}

/** True when the configured secret is a test-mode key. */
export function isStripeTestSecret(key: string): boolean {
  return key.startsWith("sk_test_");
}

/**
 * Accepts `sk_live_…` (production) or `sk_test_…` (local / staging).
 * Publishable key in the iOS app must match the same mode.
 */
export function assertUsableStripeSecret(
  key: string,
): { ok: true } | { ok: false; error: string } {
  const normalized = normalizeStripeSecret(key);

  if (!normalized.startsWith("sk_")) {
    return {
      ok: false,
      error: "STRIPE_SECRET_KEY must be a Stripe secret key (sk_live_… or sk_test_…).",
    };
  }
  if (!normalized.startsWith("sk_live_") && !normalized.startsWith("sk_test_")) {
    return {
      ok: false,
      error: "STRIPE_SECRET_KEY must start with sk_live_ or sk_test_.",
    };
  }
  // Standard Stripe secret keys are ~100+ chars. Shorter almost always means truncation.
  if (normalized.length < 100) {
    return {
      ok: false,
      error:
        "STRIPE_SECRET_KEY looks truncated. Re-copy the full sk_live_… or sk_test_… from Stripe Dashboard and paste it in Supabase Edge secrets.",
    };
  }
  return { ok: true };
}

/** Never forward raw Stripe messages that echo API key material to the client. */
export function safeStripeErrorMessage(
  message: string | undefined,
  fallback = "Stripe request failed",
): string {
  if (typeof message !== "string" || message.trim().length === 0) {
    return fallback;
  }
  if (/sk_(live|test)_|pk_(live|test)_|whsec_|rk_(live|test)_/i.test(message)) {
    if (/invalid api key/i.test(message)) {
      return "Stripe rejected the secret key. Paste the full sk_live_… or sk_test_… in Supabase Edge secrets (same mode as the iOS pk_ key).";
    }
    return fallback;
  }
  return message;
}
