/**
 * Unified customer/driver push: prefer direct APNs when configured (avoids
 * Firebase THIRD_PARTY_AUTH_ERROR), otherwise FCM, with APNs fallback.
 */

import { isApnsConfigured, sendApnsToToken, apnsConfigReport } from "./apns.ts";
import {
  isFcmConfigured,
  sendFcmToToken,
  fcmConfigReport,
  type FcmNotification,
} from "./fcm.ts";

export type DeviceTokenRow = {
  fcm_token: string;
  apns_token?: string | null;
};

export function isPushConfigured(): boolean {
  return isFcmConfigured() || isApnsConfigured();
}

export function pushConfigReport(): Record<string, unknown> {
  return {
    fcm: fcmConfigReport(),
    apns: apnsConfigReport(),
  };
}

// #region agent log
function agentLog(
  hypothesisId: string,
  location: string,
  message: string,
  data: Record<string, unknown> = {},
) {
  const payload = {
    sessionId: "0dc641",
    runId: "pre-fix",
    hypothesisId,
    location,
    message,
    data,
    timestamp: Date.now(),
  };
  console.log("[agent-debug]", JSON.stringify(payload));
  fetch("http://127.0.0.1:7868/ingest/418cc6ba-2ec5-4f6d-aca9-699e1054421b", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Debug-Session-Id": "0dc641",
    },
    body: JSON.stringify(payload),
  }).catch(() => {});
}
// #endregion

export async function sendPushToDevice(
  row: DeviceTokenRow,
  notification: FcmNotification,
): Promise<{
  ok: boolean;
  error?: string;
  transport?: string;
  raw?: unknown;
}> {
  const apnsToken = typeof row.apns_token === "string" ? row.apns_token.trim() : "";
  const fcmToken = typeof row.fcm_token === "string" ? row.fcm_token.trim() : "";
  const apnsReady = isApnsConfigured() && apnsToken.length >= 32;
  const fcmReady = isFcmConfigured() && fcmToken.length >= 20;

  // #region agent log
  agentLog("A", "pushSend.ts:sendPushToDevice", "transport readiness", {
    apnsConfigured: isApnsConfigured(),
    apnsTokenLen: apnsToken.length,
    apnsReady,
    fcmReady,
    fcmTokenLen: fcmToken.length,
    title: notification.title,
  });
  // #endregion

  // Prefer direct APNs when we have a device token — Firebase Console APNs
  // auth is what fails with THIRD_PARTY_AUTH_ERROR.
  if (apnsReady) {
    const apns = await sendApnsToToken(apnsToken, notification);
    // #region agent log
    agentLog("C", "pushSend.ts:apnsPrimary", "APNs primary result", {
      ok: apns.ok,
      error: apns.error ?? null,
      host: apns.host ?? null,
    });
    // #endregion
    if (apns.ok) {
      return { ok: true, transport: "apns", raw: apns.raw };
    }
    console.log(
      "[pushSend] APNs failed, will try FCM if available:",
      apns.error,
    );
    if (!fcmReady) {
      return { ok: false, error: apns.error, transport: "apns", raw: apns.raw };
    }
  }

  if (fcmReady) {
    const fcm = await sendFcmToToken(fcmToken, notification);
    // #region agent log
    agentLog("E", "pushSend.ts:fcm", "FCM result", {
      ok: fcm.ok,
      error: typeof fcm.error === "string" ? fcm.error.slice(0, 240) : null,
      thirdParty: typeof fcm.error === "string" &&
        /THIRD_PARTY_AUTH_ERROR/i.test(fcm.error),
    });
    // #endregion
    if (fcm.ok) {
      return { ok: true, transport: "fcm", raw: fcm.raw };
    }
    const isThirdParty =
      typeof fcm.error === "string" &&
      /THIRD_PARTY_AUTH_ERROR/i.test(fcm.error);
    if (isThirdParty && apnsReady) {
      console.log(
        "[pushSend] FCM THIRD_PARTY_AUTH_ERROR — retrying via direct APNs",
      );
      const apns = await sendApnsToToken(apnsToken, notification);
      if (apns.ok) {
        return { ok: true, transport: "apns_fallback", raw: apns.raw };
      }
      return {
        ok: false,
        error: apns.error ?? fcm.error,
        transport: "apns_fallback",
        raw: apns.raw ?? fcm.raw,
      };
    }
    return { ok: false, error: fcm.error, transport: "fcm", raw: fcm.raw };
  }

  if (!apnsReady && !fcmReady) {
    return {
      ok: false,
      error: apnsToken
        ? "apns_secrets_missing"
        : "no_apns_token_and_fcm_unavailable",
      transport: "none",
    };
  }

  return { ok: false, error: "no_transport", transport: "none" };
}
