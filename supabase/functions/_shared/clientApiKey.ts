/**
 * Validates the `apikey` header for Edge Functions that use verify_jwt = false
 * with the new `sb_publishable_…` client keys.
 *
 * Accepts:
 * - Any value in SUPABASE_PUBLISHABLE_KEYS (JSON object of named keys)
 * - SUPABASE_PUBLISHABLE_KEY (singular, local CLI)
 * - Legacy SUPABASE_ANON_KEY
 */
export function isValidClientApiKey(apikey: string | null): boolean {
  if (!apikey) return false;

  const anon = Deno.env.get("SUPABASE_ANON_KEY");
  if (anon && apikey === anon) return true;

  const singular = Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  if (singular && apikey === singular) return true;

  const keysJson = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS");
  if (keysJson) {
    try {
      const parsed = JSON.parse(keysJson) as unknown;
      if (Array.isArray(parsed) && parsed.includes(apikey)) return true;
      if (
        parsed &&
        typeof parsed === "object" &&
        Object.values(parsed as Record<string, unknown>).includes(apikey)
      ) {
        return true;
      }
    } catch {
      // fall through
    }
  }

  return false;
}

export function requireClientApiKey(
  req: Request,
  corsHeaders: Record<string, string> = {},
): Response | null {
  const apikey = req.headers.get("apikey");
  if (isValidClientApiKey(apikey)) return null;
  return Response.json(
    { error: "Unauthorized — missing or invalid apikey" },
    { status: 401, headers: corsHeaders },
  );
}

/** Client key for `createClient` (user-scoped Auth / RLS). */
export function supabaseClientKey(): string | null {
  const singular = Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  if (singular) return singular;

  const keysJson = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS");
  if (keysJson) {
    try {
      const parsed = JSON.parse(keysJson) as unknown;
      if (Array.isArray(parsed) && typeof parsed[0] === "string") {
        return parsed[0];
      }
      if (parsed && typeof parsed === "object") {
        const values = Object.values(parsed as Record<string, unknown>);
        const first = values.find((v) => typeof v === "string");
        if (typeof first === "string") return first;
      }
    } catch {
      // fall through
    }
  }

  return Deno.env.get("SUPABASE_ANON_KEY") ?? null;
}
