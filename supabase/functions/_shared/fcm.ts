/**
 * Firebase Cloud Messaging helpers for Edge Functions.
 *
 * Secrets (either works):
 * - FIREBASE_SERVICE_ACCOUNT_JSON — full service-account JSON (FCM HTTP v1)
 * - FIREBASE_CLOUD_MESSAGING_SERVER_KEY — legacy server key (fallback)
 * - FIREBASE_PROJECT_ID — optional override (defaults to chercharge-5ff77)
 */

export type FcmNotification = {
  title: string;
  body: string;
  data?: Record<string, string>;
};

type ServiceAccount = {
  project_id?: string;
  client_email: string;
  private_key: string;
};

let cachedAccessToken: { token: string; expiresAtMs: number } | null = null;

export function firebaseProjectId(): string {
  const fromEnv = Deno.env.get("FIREBASE_PROJECT_ID")?.trim();
  if (fromEnv) return fromEnv;
  const sa = parseServiceAccount();
  if (sa?.project_id) return sa.project_id;
  return "chercharge-5ff77-6566e";
}

function parseServiceAccount(): ServiceAccount | null {
  let raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON")?.trim() ?? "";
  if (!raw) {
    console.log("[fcm] FIREBASE_SERVICE_ACCOUNT_JSON empty/missing");
    return null;
  }

  // Shell / dashboard mishaps: wrapping quotes, single-line JSON with \\n, etc.
  if (
    (raw.startsWith('"') && raw.endsWith('"')) ||
    (raw.startsWith("'") && raw.endsWith("'"))
  ) {
    raw = raw.slice(1, -1).trim();
  }

  try {
    let parsed: unknown = JSON.parse(raw);
    // Double-encoded JSON string
    if (typeof parsed === "string") {
      parsed = JSON.parse(parsed);
    }
    if (!parsed || typeof parsed !== "object") {
      console.log("[fcm] service account JSON parsed but not an object");
      return null;
    }
    const obj = parsed as Record<string, unknown>;
    const clientEmail = obj.client_email;
    let privateKey = obj.private_key;
    if (typeof clientEmail !== "string" || typeof privateKey !== "string") {
      console.log(
        "[fcm] service account missing client_email or private_key",
        JSON.stringify({
          hasClientEmail: typeof clientEmail === "string",
          hasPrivateKey: typeof privateKey === "string",
        }),
      );
      return null;
    }
    // Secrets often store literal \n sequences instead of real newlines.
    if (privateKey.includes("\\n") && !privateKey.includes("\n")) {
      privateKey = privateKey.replace(/\\n/g, "\n");
    }
    console.log(
      "[fcm] Firebase service account initialized successfully",
      JSON.stringify({
        project_id: typeof obj.project_id === "string" ? obj.project_id : null,
        client_email: clientEmail,
        privateKeyLength: privateKey.length,
        privateKeyLooksPem: privateKey.includes("BEGIN PRIVATE KEY"),
      }),
    );
    return {
      project_id: typeof obj.project_id === "string" ? obj.project_id : undefined,
      client_email: clientEmail,
      private_key: privateKey,
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const stack = error instanceof Error ? error.stack : undefined;
    console.error("[fcm] failed to parse FIREBASE_SERVICE_ACCOUNT_JSON:", message);
    console.error("[fcm] stack trace:", stack ?? "(no stack)");
    return null;
  }
}

/** Safe diagnostics — never returns secret material. */
export function fcmConfigReport(): Record<string, unknown> {
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON") ?? "";
  const legacy = legacyServerKey();
  const sa = parseServiceAccount();
  return {
    hasServiceAccountEnv: raw.trim().length > 0,
    serviceAccountEnvLength: raw.trim().length,
    serviceAccountParsed: sa != null,
    hasClientEmail: sa?.client_email != null,
    clientEmailDomain: sa?.client_email?.includes("@")
      ? sa.client_email.split("@")[1]
      : null,
    serviceAccountProjectId: sa?.project_id ?? null,
    hasPrivateKey: typeof sa?.private_key === "string" && sa.private_key.length > 20,
    privateKeyLooksPem: sa?.private_key?.includes("BEGIN PRIVATE KEY") === true,
        hasLegacyServerKey: legacy != null,
    projectIdUsedForSend: firebaseProjectId(),
    expectedIosProjectId: "chercharge-5ff77-6566e",
    expectedIosSenderId: "917525221485",
  };
}

function legacyServerKey(): string | null {
  const key =
    Deno.env.get("FIREBASE_CLOUD_MESSAGING_SERVER_KEY")?.trim() ||
    Deno.env.get("FCM_SERVER_KEY")?.trim();
  return key || null;
}

export function isFcmConfigured(): boolean {
  return parseServiceAccount() != null || legacyServerKey() != null;
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

async function getAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Date.now();
  if (cachedAccessToken && cachedAccessToken.expiresAtMs > now + 60_000) {
    console.log("[fcm] reusing cached OAuth access token");
    return cachedAccessToken.token;
  }

  console.log("[fcm] requesting OAuth access token for", sa.client_email);
  const iat = Math.floor(now / 1000);
  const exp = iat + 3600;
  const header = { alg: "RS256", typ: "JWT" };
  const claim = {
    iss: sa.client_email,
    sub: sa.client_email,
    aud: "https://oauth2.googleapis.com/token",
    iat,
    exp,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  };

  const unsigned =
    `${base64UrlEncode(JSON.stringify(header))}.${base64UrlEncode(JSON.stringify(claim))}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const jwt = `${unsigned}.${base64UrlEncode(signature)}`;

  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  const tokenJson = await tokenRes.json();
  console.log(
    "[fcm] OAuth token response:",
    JSON.stringify({
      status: tokenRes.status,
      ok: tokenRes.ok,
      hasAccessToken: typeof tokenJson.access_token === "string",
      expires_in: tokenJson.expires_in ?? null,
      error: tokenJson.error ?? null,
      error_description: tokenJson.error_description ?? null,
    }),
  );
  if (!tokenRes.ok || typeof tokenJson.access_token !== "string") {
    throw new Error(
      typeof tokenJson.error === "string"
        ? `FCM auth failed: ${tokenJson.error}`
        : "FCM auth failed",
    );
  }

  cachedAccessToken = {
    token: tokenJson.access_token,
    expiresAtMs: now + Math.min(3500, Number(tokenJson.expires_in) || 3500) * 1000,
  };
  console.log("[fcm] Firebase Admin/OAuth initialized successfully");
  return cachedAccessToken.token;
}

async function sendViaHttpV1(
  token: string,
  notification: FcmNotification,
): Promise<{ ok: boolean; error?: string; raw?: unknown }> {
  const sa = parseServiceAccount();
  if (!sa) {
    console.log("[fcm] sendViaHttpV1 aborted — missing_service_account");
    return { ok: false, error: "missing_service_account" };
  }

  const accessToken = await getAccessToken(sa);
  const projectId = firebaseProjectId();
  const data: Record<string, string> = {};
  if (notification.data) {
    for (const [k, v] of Object.entries(notification.data)) {
      data[k] = String(v);
    }
  }

  console.log(
    "[fcm] HTTP v1 send starting",
    JSON.stringify({
      projectId,
      tokenPrefix: token.slice(0, 12),
      tokenLength: token.length,
      title: notification.title,
    }),
  );

  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: {
            title: notification.title,
            body: notification.body,
          },
          data,
          apns: {
            headers: {
              "apns-priority": "10",
              "apns-push-type": "alert",
            },
            payload: {
              aps: {
                alert: {
                  title: notification.title,
                  body: notification.body,
                },
                sound: "default",
                "content-available": 1,
              },
            },
          },
        },
      }),
    },
  );

  const responseText = await res.text();
  let responseJson: unknown = responseText;
  try {
    responseJson = JSON.parse(responseText);
  } catch {
    // keep text
  }
  console.log(
    "[fcm] full Firebase send response (HTTP v1):",
    JSON.stringify({
      status: res.status,
      ok: res.ok,
      body: responseJson,
    }),
  );

  if (res.ok) return { ok: true, raw: responseJson };
  // Drop stale tokens so the next registration replaces them.
  if (res.status === 404 || /UNREGISTERED|INVALID_ARGUMENT/i.test(responseText)) {
    return { ok: false, error: "unregistered", raw: responseJson };
  }
  const detail =
    typeof responseJson === "object" && responseJson != null
      ? JSON.stringify(responseJson)
      : responseText.slice(0, 500);
  return {
    ok: false,
    error: `http_${res.status}:${detail}`,
    raw: responseJson,
  };
}

async function sendViaLegacy(
  token: string,
  notification: FcmNotification,
): Promise<{ ok: boolean; error?: string; raw?: unknown }> {
  const key = legacyServerKey();
  if (!key) {
    console.log("[fcm] sendViaLegacy aborted — missing_server_key");
    return { ok: false, error: "missing_server_key" };
  }

  const data: Record<string, string> = {};
  if (notification.data) {
    for (const [k, v] of Object.entries(notification.data)) {
      data[k] = String(v);
    }
  }

  console.log(
    "[fcm] legacy FCM send starting",
    JSON.stringify({
      tokenPrefix: token.slice(0, 12),
      tokenLength: token.length,
      title: notification.title,
    }),
  );

  const res = await fetch("https://fcm.googleapis.com/fcm/send", {
    method: "POST",
    headers: {
      Authorization: `key=${key}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      to: token,
      priority: "high",
      content_available: true,
      notification: {
        title: notification.title,
        body: notification.body,
        sound: "default",
      },
      data,
    }),
  });

  const json = await res.json().catch(() => ({}));
  console.log(
    "[fcm] full Firebase send response (legacy):",
    JSON.stringify({ status: res.status, ok: res.ok, body: json }),
  );
  if (!res.ok) return { ok: false, error: `http_${res.status}`, raw: json };
  if (json.failure && Number(json.failure) > 0) {
    const result = Array.isArray(json.results) ? json.results[0] : null;
    const err = result?.error ?? "legacy_failure";
    if (err === "NotRegistered" || err === "InvalidRegistration") {
      return { ok: false, error: "unregistered", raw: json };
    }
    return { ok: false, error: String(err), raw: json };
  }
  return { ok: true, raw: json };
}

export async function sendFcmToToken(
  token: string,
  notification: FcmNotification,
): Promise<{ ok: boolean; error?: string; raw?: unknown }> {
  try {
    if (parseServiceAccount()) {
      console.log("[fcm] using HTTP v1 transport");
      return await sendViaHttpV1(token, notification);
    }
    console.log("[fcm] using legacy server-key transport");
    return await sendViaLegacy(token, notification);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const stack = error instanceof Error ? error.stack : undefined;
    console.error("[fcm] sendFcmToToken caught error:", message);
    console.error("[fcm] stack trace:", stack ?? "(no stack)");
    throw error;
  }
}
