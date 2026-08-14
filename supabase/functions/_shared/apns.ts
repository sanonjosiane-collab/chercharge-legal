/**
 * Direct Apple Push Notification service (APNs) via Auth Key (.p8).
 *
 * Used when FCM returns THIRD_PARTY_AUTH_ERROR (Firebase Console missing/invalid
 * Apple APNs key) — Edge talks to Apple with the same .p8 you would upload there.
 *
 * Secrets:
 * - APNS_AUTH_KEY — PEM contents of AuthKey_XXXX.p8
 * - APNS_KEY_ID — Key ID (e.g. D33DRVGS9B)
 * - APNS_TEAM_ID — Apple Team ID (e.g. 7N56AZ3JBJ)
 * - APNS_BUNDLE_ID — app bundle id (default Chercharge.Chercharge)
 * - APNS_PRODUCTION — "true" for api.push.apple.com; otherwise sandbox first
 */

import type { FcmNotification } from "./fcm.ts";

let cachedJwt: { token: string; expiresAtMs: number } | null = null;

export function isApnsConfigured(): boolean {
  return (
    !!apnsAuthKeyPem() &&
    !!Deno.env.get("APNS_KEY_ID")?.trim() &&
    !!Deno.env.get("APNS_TEAM_ID")?.trim()
  );
}

export function apnsConfigReport(): Record<string, unknown> {
  const key = apnsAuthKeyPem();
  return {
    configured: isApnsConfigured(),
    hasAuthKey: key != null,
    authKeyLength: key?.length ?? 0,
    authKeyLooksPem: key?.includes("BEGIN PRIVATE KEY") === true,
    keyId: Deno.env.get("APNS_KEY_ID")?.trim() || null,
    teamId: Deno.env.get("APNS_TEAM_ID")?.trim() || null,
    bundleId: apnsBundleId(),
    production: apnsProductionForced(),
  };
}

function apnsAuthKeyPem(): string | null {
  let raw = Deno.env.get("APNS_AUTH_KEY")?.trim() ?? "";
  if (!raw) return null;
  if (
    (raw.startsWith('"') && raw.endsWith('"')) ||
    (raw.startsWith("'") && raw.endsWith("'"))
  ) {
    raw = raw.slice(1, -1).trim();
  }
  if (raw.includes("\\n") && !raw.includes("\n")) {
    raw = raw.replace(/\\n/g, "\n");
  }
  if (!raw.includes("BEGIN PRIVATE KEY")) return null;
  return raw;
}

function apnsBundleId(): string {
  return (
    Deno.env.get("APNS_BUNDLE_ID")?.trim() ||
    "Chercharge.Chercharge"
  );
}

function apnsProductionForced(): boolean | null {
  const v = Deno.env.get("APNS_PRODUCTION")?.trim().toLowerCase();
  if (v === "true" || v === "1") return true;
  if (v === "false" || v === "0") return false;
  return null;
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const cleaned = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\\n/g, "\n")
    .replace(/\s+/g, "");
  const binary = atob(cleaned);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

function base64UrlEncode(data: ArrayBuffer | Uint8Array | string): string {
  let bytes: Uint8Array;
  if (typeof data === "string") {
    bytes = new TextEncoder().encode(data);
  } else if (data instanceof Uint8Array) {
    bytes = data;
  } else {
    bytes = new Uint8Array(data);
  }
  let binary = "";
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]!);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

/** Debug-only: mint provider JWT without sending a push. */
export async function mintApnsJwtForDebug(): Promise<{
  ok: boolean;
  error?: string;
  keyId?: string | null;
  teamId?: string | null;
  jwtLength?: number;
}> {
  try {
    const jwt = await getApnsProviderToken();
    return {
      ok: true,
      keyId: Deno.env.get("APNS_KEY_ID")?.trim() || null,
      teamId: Deno.env.get("APNS_TEAM_ID")?.trim() || null,
      jwtLength: jwt.length,
    };
  } catch (error) {
    return {
      ok: false,
      error: error instanceof Error ? error.message : String(error),
      keyId: Deno.env.get("APNS_KEY_ID")?.trim() || null,
      teamId: Deno.env.get("APNS_TEAM_ID")?.trim() || null,
    };
  }
}

async function getApnsProviderToken(): Promise<string> {
  const now = Date.now();
  if (cachedJwt && cachedJwt.expiresAtMs > now + 60_000) {
    return cachedJwt.token;
  }

  const pem = apnsAuthKeyPem();
  const keyId = Deno.env.get("APNS_KEY_ID")?.trim();
  const teamId = Deno.env.get("APNS_TEAM_ID")?.trim();
  if (!pem || !keyId || !teamId) {
    throw new Error("APNs secrets missing (APNS_AUTH_KEY, APNS_KEY_ID, APNS_TEAM_ID)");
  }

  const iat = Math.floor(now / 1000);
  const header = { alg: "ES256", kid: keyId };
  const claim = { iss: teamId, iat };
  const unsigned =
    `${base64UrlEncode(JSON.stringify(header))}.${base64UrlEncode(JSON.stringify(claim))}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(pem),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(unsigned),
  );
  const jwt = `${unsigned}.${base64UrlEncode(signature)}`;

  // Apple tokens are valid up to 1 hour; refresh earlier.
  cachedJwt = { token: jwt, expiresAtMs: now + 50 * 60_000 };
  console.log("[apns] provider JWT minted", JSON.stringify({ keyId, teamId }));
  return jwt;
}

function normalizeApnsDeviceToken(token: string): string {
  return token.trim().replace(/\s+/g, "").toLowerCase();
}

async function postToApnsHost(
  host: string,
  deviceToken: string,
  jwt: string,
  notification: FcmNotification,
): Promise<{ ok: boolean; status: number; reason?: string; raw?: unknown }> {
  const topic = apnsBundleId();
  const data: Record<string, string> = {};
  if (notification.data) {
    for (const [k, v] of Object.entries(notification.data)) {
      data[k] = String(v);
    }
  }

  const payload = {
    aps: {
      alert: {
        title: notification.title,
        body: notification.body,
      },
      sound: "default",
      "content-available": 1,
    },
    ...data,
  };

  console.log(
    "[apns] sending",
    JSON.stringify({
      host,
      topic,
      tokenPrefix: deviceToken.slice(0, 12),
      tokenLength: deviceToken.length,
      title: notification.title,
    }),
  );

  const res = await fetch(`https://${host}/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": topic,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  });

  const text = await res.text();
  let json: unknown = text;
  try {
    json = text ? JSON.parse(text) : {};
  } catch {
    // keep text
  }

  const reason =
    typeof json === "object" &&
      json != null &&
      typeof (json as { reason?: unknown }).reason === "string"
      ? (json as { reason: string }).reason
      : undefined;

  console.log(
    "[apns] full Apple send response:",
    JSON.stringify({ host, status: res.status, ok: res.ok, body: json }),
  );

  return {
    ok: res.ok,
    status: res.status,
    reason,
    raw: json,
  };
}

/**
 * Send an alert via APNs HTTP/2. Tries sandbox and/or production based on
 * APNS_PRODUCTION and BadEnvironment / BadDeviceToken responses.
 */
export async function sendApnsToToken(
  deviceToken: string,
  notification: FcmNotification,
): Promise<{ ok: boolean; error?: string; raw?: unknown; host?: string }> {
  const token = normalizeApnsDeviceToken(deviceToken);
  if (token.length < 32) {
    return { ok: false, error: "invalid_apns_token" };
  }

  try {
    let jwt = await getApnsProviderToken();
    const forced = apnsProductionForced();
    // Always try both environments; order by preference. Forced false used to
    // sandbox-only and never fall back — BadDeviceToken then permanently failed.
    const hosts =
      forced === true
        ? ["api.push.apple.com", "api.sandbox.push.apple.com"]
        : ["api.sandbox.push.apple.com", "api.push.apple.com"];

    let last: { ok: boolean; status: number; reason?: string; raw?: unknown; host: string } | null =
      null;

    for (const host of hosts) {
      const result = await postToApnsHost(host, token, jwt, notification);
      last = { ...result, host };
      if (result.ok) {
        return { ok: true, raw: result.raw, host };
      }
      // Wrong environment / unknown token env — try the other host.
      if (
        result.reason === "BadEnvironment" ||
        result.reason === "BadDeviceToken" ||
        result.status === 400 ||
        result.status === 403
      ) {
        continue;
      }
      break;
    }

    const reason = last?.reason ?? `http_${last?.status ?? "unknown"}`;
    if (
      reason === "BadDeviceToken" ||
      reason === "Unregistered" ||
      reason === "ExpiredToken"
    ) {
      return { ok: false, error: "unregistered", raw: last?.raw, host: last?.host };
    }
    return {
      ok: false,
      error: `apns_${reason}`,
      raw: last?.raw,
      host: last?.host,
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("[apns] sendApnsToToken error:", message);
    return { ok: false, error: message };
  }
}
