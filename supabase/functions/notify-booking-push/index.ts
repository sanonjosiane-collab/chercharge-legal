// Sends booking push alerts.
//
// Customer inspection ready:
//   POST { booking_id, phase: "preTrip"|"postTrip" }
//
// Customer status:
//   POST { booking_id, event: "driver_arrived"|"driver_en_route" }
//
// Trigger path (AFTER INSERT on push_events via pg_net):
//   POST { booking_id, phase|event, push_event_id, from_push_event: true }
//
// Driver approval:
//   POST { booking_id, event: "driver_pickup_approved"|"driver_return_approved" }
//
// Auth: apikey (publishable) or service-role Bearer.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  isValidClientApiKey,
  requireClientApiKey,
} from "../_shared/clientApiKey.ts";
import { isApnsConfigured, sendApnsToToken, mintApnsJwtForDebug } from "../_shared/apns.ts";
import {
  isPushConfigured,
  pushConfigReport,
  sendPushToDevice,
} from "../_shared/pushSend.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

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

  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const authHeader = req.headers.get("authorization") ?? "";
  const bearer = authHeader.toLowerCase().startsWith("bearer ")
    ? authHeader.slice(7).trim()
    : "";
  const isService = serviceRole.length > 0 && bearer === serviceRole;

  if (!isService) {
    const unauthorized = requireClientApiKey(req, CORS_HEADERS);
    if (unauthorized) return unauthorized;
  } else if (!isValidClientApiKey(req.headers.get("apikey")) && !isService) {
    // service role alone is enough
  }

  try {
    const body = await req.json();
    console.log("[notify-booking-push] request body:", JSON.stringify(body));

    // #region agent log
    // Debug probe: inspect push config + tokens + optional APNs dry-run (no booking required).
    if (body?.debug_probe === true && body?.debug_session === "0dc641") {
      const admin = createAdminClient();
      const { data: tokens, error: tokensError } = await admin
        .from("device_tokens")
        .select("customer_email, fcm_token, apns_token, updated_at, platform")
        .order("updated_at", { ascending: false })
        .limit(20);

      const tokenSummary = (tokens ?? []).map((t) => ({
        email: t.customer_email,
        platform: t.platform,
        fcmLen: typeof t.fcm_token === "string" ? t.fcm_token.length : 0,
        apnsLen: typeof t.apns_token === "string" ? t.apns_token.length : 0,
        hasApns: typeof t.apns_token === "string" && t.apns_token.length >= 32,
        updated_at: t.updated_at,
      }));

      const jwtProbe = await mintApnsJwtForDebug();
      let apnsSendProbe: Record<string, unknown> | null = null;
      let fcmSendProbe: Record<string, unknown> | null = null;
      const firstApns = (tokens ?? []).find(
        (t) => typeof t.apns_token === "string" && t.apns_token.length >= 32,
      );
      if (body?.apns_dry_run === true && firstApns?.apns_token) {
        const result = await sendApnsToToken(String(firstApns.apns_token), {
          title: "Chercharge debug",
          body: "APNs dry-run probe",
          data: { kind: "debugProbe" },
        });
        apnsSendProbe = {
          ok: result.ok,
          error: result.error ?? null,
          host: result.host ?? null,
          rawType: typeof result.raw,
        };
      }
      if (body?.fcm_dry_run === true && (tokens ?? []).length > 0) {
        const { sendFcmToToken } = await import("../_shared/fcm.ts");
        const row = (tokens ?? [])[0]!;
        const result = await sendFcmToToken(String(row.fcm_token), {
          title: "Chercharge debug",
          body: "FCM dry-run probe",
          data: { kind: "debugProbe" },
        });
        fcmSendProbe = {
          ok: result.ok,
          error: typeof result.error === "string"
            ? result.error.slice(0, 400)
            : null,
          thirdParty: typeof result.error === "string" &&
            /THIRD_PARTY_AUTH_ERROR/i.test(result.error),
        };
      }

      const { data: recentEvents } = await admin
        .from("push_events")
        .select(
          "id, booking_id, event, created_at, delivered_at, fcm_sent_at, invoke_request_id",
        )
        .order("created_at", { ascending: false })
        .limit(10);

      let httpResponses: unknown[] = [];
      try {
        const { data: httpRows } = await admin.rpc("debug_list_http_responses" as never);
        httpResponses = Array.isArray(httpRows) ? httpRows : [];
      } catch {
        // optional RPC may not exist
      }
      // Fallback: read net._http_response via raw SQL isn't available; skip.

      const report = {
        ok: true,
        debug_probe: true,
        pushConfigured: isPushConfigured(),
        apnsConfigured: isApnsConfigured(),
        diagnostics: pushConfigReport(),
        jwtProbe,
        tokenCount: tokenSummary.length,
        tokensWithApns: tokenSummary.filter((t) => t.hasApns).length,
        tokenSummary,
        tokensError: tokensError?.message ?? null,
        apnsSendProbe,
        fcmSendProbe,
        recentEvents: recentEvents ?? [],
        httpResponses,
      };

      agentLog("A", "notify-booking-push:debug_probe", "probe complete", {
        tokenCount: report.tokenCount,
        tokensWithApns: report.tokensWithApns,
        apnsConfigured: report.apnsConfigured,
        jwtOk: jwtProbe.ok,
        apnsSendOk: apnsSendProbe?.ok ?? null,
        fcmSendOk: fcmSendProbe?.ok ?? null,
        fcmThirdParty: fcmSendProbe?.thirdParty ?? null,
      });
      agentLog("B", "notify-booking-push:debug_probe", "jwt probe", {
        jwtOk: jwtProbe.ok,
        error: jwtProbe.error ?? null,
      });
      agentLog("C", "notify-booking-push:debug_probe", "apns send probe", {
        ran: apnsSendProbe != null,
        ...(apnsSendProbe ?? {}),
      });
      agentLog("E", "notify-booking-push:debug_probe", "fcm send probe", {
        ran: fcmSendProbe != null,
        ...(fcmSendProbe ?? {}),
      });

      return Response.json(report, { headers: CORS_HEADERS });
    }
    // #endregion

    const bookingId = asUUID(body?.booking_id);
    console.log("[notify-booking-push] booking ID:", bookingId);
    if (!bookingId) {
      console.log("[notify-booking-push] invalid booking_id — rejecting");
      return Response.json(
        { error: "booking_id must be a UUID" },
        { status: 400, headers: CORS_HEADERS },
      );
    }

    const admin = createAdminClient();
    const { data: booking, error } = await admin
      .from("bookings")
      .select(
        "id, status, customer_id, driver_id, vehicle_name, vehicle_make, vehicle_model, pre_trip_inspection, post_trip_inspection",
      )
      .eq("id", bookingId)
      .maybeSingle();

    console.log("[notify-booking-push] bookings query result:", JSON.stringify({
      booking,
      error: error ? { message: error.message, code: error.code, details: error.details } : null,
    }));

    if (error) {
      console.log("[notify-booking-push] bookings query error:", error.message);
      return Response.json(
        { error: error.message },
        { status: 400, headers: CORS_HEADERS },
      );
    }
    if (!booking) {
      console.log("[notify-booking-push] booking not found for id:", bookingId);
      return Response.json(
        { error: "Booking not found" },
        { status: 404, headers: CORS_HEADERS },
      );
    }

    const recipientUserId = booking.customer_id;
    console.log("[notify-booking-push] recipient user ID (customer_id):", recipientUserId);
    console.log("[notify-booking-push] booking.status:", booking.status);
    console.log("[notify-booking-push] booking.driver_id:", booking.driver_id);

    const event = typeof body?.event === "string" ? body.event : null;
    const phaseHint =
      body?.phase === "postTrip" || body?.phase === "preTrip"
        ? body.phase
        : null;
    const fromPushEvent = body?.from_push_event === true;
    const pushEventId =
      typeof body?.push_event_id === "string" ? body.push_event_id : null;
    console.log("[notify-booking-push] parsed flags:", JSON.stringify({
      event,
      phaseHint,
      fromPushEvent,
      pushEventId,
    }));

    // Driver approval events — best-effort (FCM if token exists, else skip).
    if (
      event === "driver_pickup_approved" ||
      event === "driver_return_approved"
    ) {
      console.log("[notify-booking-push] routing to notifyDriverApproval");
      return await notifyDriverApproval(admin, booking, event, {
        fromPushEvent,
        pushEventId,
      });
    }

    // Customer trip-status pushes (arrive / en route).
    if (event === "driver_arrived" || event === "driver_en_route") {
      console.log("[notify-booking-push] routing to notifyCustomerStatus");
      return await notifyCustomerStatus(admin, booking, event, {
        fromPushEvent,
        pushEventId,
      });
    }

    let phase: "preTrip" | "postTrip" | null = phaseHint;
    if (!phase && event === "inspection_ready_preTrip") phase = "preTrip";
    if (!phase && event === "inspection_ready_postTrip") phase = "postTrip";
    if (!phase) {
      if (booking.status === "awaitingCustomerApproval") phase = "preTrip";
      else if (
        booking.status === "awaitingReturnApproval" ||
        booking.status === "awaitingPostTripInspection"
      ) {
        phase = "postTrip";
      }
    }
    console.log("[notify-booking-push] resolved phase:", phase);

    if (phase === "preTrip") {
      if (
        booking.status !== "awaitingCustomerApproval" ||
        !booking.pre_trip_inspection
      ) {
        console.log("[notify-booking-push] skipping: pre-trip not ready", JSON.stringify({
          status: booking.status,
          hasPreTripInspection: !!booking.pre_trip_inspection,
        }));
        return Response.json(
          {
            ok: false,
            skipped: true,
            error: "Pre-trip inspection is not ready for review yet.",
          },
          { headers: CORS_HEADERS },
        );
      }
    } else if (phase === "postTrip") {
      const returnReadyStatus =
        booking.status === "awaitingReturnApproval" ||
        booking.status === "awaitingPostTripInspection";
      if (!returnReadyStatus || !booking.post_trip_inspection) {
        console.log("[notify-booking-push] skipping: post-trip not ready", JSON.stringify({
          status: booking.status,
          hasPostTripInspection: !!booking.post_trip_inspection,
        }));
        return Response.json(
          {
            ok: false,
            skipped: true,
            error: "Return inspection is not ready for review yet.",
          },
          { headers: CORS_HEADERS },
        );
      }
    } else {
      console.log("[notify-booking-push] skipping: no inspection phase");
      return Response.json(
        { ok: false, skipped: true, error: "No inspection phase to notify." },
        { headers: CORS_HEADERS },
      );
    }

    const copy = notificationCopy(phase);
    // Direct callers insert a push_event (trigger also fires). Always attempt FCM
    // here so delivery works even if Vault/pg_net is misconfigured. The
    // from_push_event path skips when fcm_sent_at is already set (idempotent).
    let recordedPushEventId: string | null = pushEventId;
    if (!fromPushEvent) {
      console.log(
        "[notify-booking-push] direct call — inserting push_event then sending FCM",
        JSON.stringify({ bookingId, recipientUserId }),
      );
      recordedPushEventId = await insertPushEvent(admin, {
        bookingId,
        recipientUserId: booking.customer_id,
        event: phase === "preTrip"
          ? "inspection_ready_preTrip"
          : "inspection_ready_postTrip",
        title: copy.title,
        body: copy.body,
      });
      console.log(
        "[notify-booking-push] push_event insert done:",
        recordedPushEventId,
      );
    } else if (pushEventId) {
      const already = await wasFcmSent(admin, pushEventId);
      if (already) {
        console.log(
          "[notify-booking-push] skipping — fcm_sent_at already set for",
          pushEventId,
        );
        return Response.json(
          {
            ok: true,
            sent: 0,
            skipped: true,
            alreadySent: true,
            pushEventId,
            fromPushEvent: true,
            phase,
          },
          { headers: CORS_HEADERS },
        );
      }
    }

    const pushConfigured = isPushConfigured();
    const pushReport = pushConfigReport();
    console.log(
      "[notify-booking-push] push configured:",
      pushConfigured,
      "report:",
      JSON.stringify(pushReport),
    );

    if (!pushConfigured) {
      const probed = [
        "FIREBASE_SERVICE_ACCOUNT_JSON",
        "FIREBASE_CLOUD_MESSAGING_SERVER_KEY",
        "FCM_SERVER_KEY",
        "FIREBASE_PROJECT_ID",
        "APNS_AUTH_KEY",
        "APNS_KEY_ID",
        "APNS_TEAM_ID",
        "APNS_BUNDLE_ID",
        "SUPABASE_URL",
      ].map((name) => ({
        name,
        length: (Deno.env.get(name) ?? "").length,
      }));
      console.log(
        "[notify-booking-push] push not configured — skipping send. probedSecrets:",
        JSON.stringify(probed),
      );
      // push_events was recorded — foreground customer app can still alert via status poll.
      return Response.json(
        {
          ok: true,
          sent: 0,
          skipped: true,
          pushEventRecorded: true,
          fromPushEvent,
          error:
            "Push secrets missing. Set FIREBASE_SERVICE_ACCOUNT_JSON and/or APNS_AUTH_KEY + APNS_KEY_ID + APNS_TEAM_ID, then redeploy notify-booking-push.",
          diagnostics: {
            ...pushReport,
            probedSecrets: probed,
          },
          phase,
        },
        { headers: CORS_HEADERS },
      );
    }

    console.log(
      "[notify-booking-push] loading device tokens for recipient:",
      recipientUserId,
    );
    const tokens = await loadTokensForCustomer(admin, booking.customer_id);
    console.log(
      "[notify-booking-push] device token(s) found:",
      tokens.length,
      JSON.stringify(tokens.map((t) => ({
        fcm: t.fcm_token?.slice(0, 12),
        apns: t.apns_token ? t.apns_token.slice(0, 12) : null,
      }))),
    );
    if (tokens.length === 0) {
      console.log(
        "[notify-booking-push] no device tokens for customer — skipping send",
      );
      return Response.json(
        {
          ok: true,
          sent: 0,
          skipped: true,
          pushEventRecorded: true,
          fromPushEvent,
          error:
            "No device tokens registered for this customer. Open the customer app and allow notifications.",
          phase,
        },
        { headers: CORS_HEADERS },
      );
    }

    const data = {
      jobID: booking.id,
      kind: "inspectionReady",
      phase,
    };
    console.log(
      "[notify-booking-push] sending push notification:",
      JSON.stringify({ title: copy.title, body: copy.body, data }),
    );

    let sent = 0;
    const stale: string[] = [];
    const failures: string[] = [];
    const transports: string[] = [];
    for (const row of tokens) {
      console.log(
        "[notify-booking-push] calling sendPushToDevice",
        JSON.stringify({
          fcmPrefix: row.fcm_token?.slice(0, 12),
          hasApns: !!row.apns_token,
        }),
      );
      const result = await sendPushToDevice(row, {
        title: copy.title,
        body: copy.body,
        data,
      });
      console.log(
        "[notify-booking-push] full push send response:",
        JSON.stringify(result),
      );
      if (result.ok) {
        sent += 1;
        if (result.transport) transports.push(result.transport);
      } else if (result.error === "unregistered") {
        stale.push(row.fcm_token);
      } else if (result.error) {
        failures.push(humanizeFcmFailure(result.error));
      }
    }

    console.log("[notify-booking-push] send summary:", JSON.stringify({
      sent,
      tokenCount: tokens.length,
      staleCount: stale.length,
      failures,
      transports,
    }));

    if (stale.length > 0) {
      console.log(
        "[notify-booking-push] deleting stale tokens:",
        JSON.stringify(stale),
      );
      await admin.from("device_tokens").delete().in("fcm_token", stale);
    }

    if (sent > 0 && recordedPushEventId) {
      console.log(
        "[notify-booking-push] marking push_event fcm_sent:",
        recordedPushEventId,
      );
      await markPushEventFcmSent(admin, recordedPushEventId);
    }

    const thirdPartyAuth = failures.some((f) =>
      /THIRD_PARTY_AUTH_ERROR/i.test(f)
    );
    const missingApnsToken = tokens.every((t) => !t.apns_token) &&
      isApnsConfigured() === false;

    return Response.json(
      {
        ok: sent > 0,
        sent,
        tokenCount: tokens.length,
        removedStale: stale.length,
        failures,
        phase,
        transport: transports[0] ?? "none",
        transports,
        pushEventRecorded: true,
        fromPushEvent,
        pushEventId: recordedPushEventId,
        error: sent > 0
          ? undefined
          : thirdPartyAuth && !isApnsConfigured()
          ? "FCM APNs auth failed (THIRD_PARTY_AUTH_ERROR). Set APNS_AUTH_KEY / APNS_KEY_ID / APNS_TEAM_ID Edge secrets (or upload the .p8 in Firebase Console → Cloud Messaging), then rebuild the customer app so apns_token is registered."
          : thirdPartyAuth
          ? "FCM APNs auth failed and direct APNs could not send (missing apns_token on device_tokens?). Rebuild/open the customer app with notifications allowed so the APNs device token uploads."
          : failures[0] ?? "Push send failed for all device tokens.",
        diagnostics: {
          ...pushConfigReport(),
          missingApnsTokenHint: missingApnsToken,
        },
      },
      { headers: CORS_HEADERS },
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    const stack = error instanceof Error ? error.stack : undefined;
    console.error("[notify-booking-push] caught error:", message);
    console.error("[notify-booking-push] stack trace:", stack ?? "(no stack)");
    return Response.json(
      { error: message },
      { status: 500, headers: CORS_HEADERS },
    );
  }
});

async function notifyCustomerStatus(
  admin: ReturnType<typeof createClient>,
  booking: {
    id: string;
    customer_id: string | null;
    status: string;
    vehicle_name?: string | null;
    vehicle_make?: string | null;
    vehicle_model?: string | null;
  },
  event: "driver_arrived" | "driver_en_route",
  opts: { fromPushEvent: boolean; pushEventId: string | null },
) {
  if (!booking.customer_id) {
    return Response.json(
      { ok: false, skipped: true, error: "Booking has no customer_id." },
      { headers: CORS_HEADERS },
    );
  }

  const vehicle =
    booking.vehicle_name ||
    [booking.vehicle_make, booking.vehicle_model].filter(Boolean).join(" ") ||
    "your EV";
  const title = event === "driver_arrived" ? "Concierge arrived" : "Pickup update";
  const body = event === "driver_arrived"
    ? `Your concierge is with ${vehicle}. You’ll be notified when the inspection is ready to review.`
    : `Your Chercharge concierge is on the way to pick up ${vehicle}.`;

  let recordedPushEventId = opts.pushEventId;
  if (!opts.fromPushEvent) {
    recordedPushEventId = await insertPushEvent(admin, {
      bookingId: booking.id,
      recipientUserId: booking.customer_id,
      event,
      title,
      body,
    });
  } else if (opts.pushEventId && await wasFcmSent(admin, opts.pushEventId)) {
    return Response.json(
      {
        ok: true,
        sent: 0,
        skipped: true,
        alreadySent: true,
        event,
        fromPushEvent: true,
      },
      { headers: CORS_HEADERS },
    );
  }

  return await deliverCustomerFcm(admin, {
    customerId: booking.customer_id,
    title,
    body,
    data: {
      jobID: booking.id,
      kind: event === "driver_arrived" ? "driverArrived" : "driverEnRoute",
      status: event === "driver_arrived" ? "driverArrived" : "driverEnRoute",
    },
    pushEventId: recordedPushEventId,
    fromPushEvent: opts.fromPushEvent,
    event,
  });
}

async function deliverCustomerFcm(
  admin: ReturnType<typeof createClient>,
  args: {
    customerId: string;
    title: string;
    body: string;
    data: Record<string, string>;
    pushEventId: string | null;
    fromPushEvent: boolean;
    event?: string;
    phase?: string;
  },
) {
  if (!isPushConfigured()) {
    return Response.json(
      {
        ok: true,
        sent: 0,
        skipped: true,
        pushEventRecorded: true,
        fromPushEvent: args.fromPushEvent,
        error:
          "Push secrets missing. Set FIREBASE_SERVICE_ACCOUNT_JSON and/or APNS_AUTH_KEY + APNS_KEY_ID + APNS_TEAM_ID.",
        diagnostics: pushConfigReport(),
        event: args.event,
        phase: args.phase,
      },
      { headers: CORS_HEADERS },
    );
  }

  const tokens = await loadTokensForCustomer(admin, args.customerId);
  if (tokens.length === 0) {
    return Response.json(
      {
        ok: true,
        sent: 0,
        skipped: true,
        pushEventRecorded: true,
        fromPushEvent: args.fromPushEvent,
        error:
          "No device tokens registered for this customer. Open the customer app and allow notifications.",
        event: args.event,
        phase: args.phase,
      },
      { headers: CORS_HEADERS },
    );
  }

  let sent = 0;
  const stale: string[] = [];
  const failures: string[] = [];
  const transports: string[] = [];
  for (const row of tokens) {
    const result = await sendPushToDevice(row, {
      title: args.title,
      body: args.body,
      data: args.data,
    });
    if (result.ok) {
      sent += 1;
      if (result.transport) transports.push(result.transport);
    } else if (result.error === "unregistered") {
      stale.push(row.fcm_token);
    } else if (result.error) {
      failures.push(humanizeFcmFailure(result.error));
    }
  }

  if (stale.length > 0) {
    await admin.from("device_tokens").delete().in("fcm_token", stale);
  }
  if (sent > 0 && args.pushEventId) {
    await markPushEventFcmSent(admin, args.pushEventId);
  }

  const thirdPartyAuth = failures.some((f) =>
    /THIRD_PARTY_AUTH_ERROR/i.test(f)
  );

  return Response.json(
    {
      ok: sent > 0,
      sent,
      tokenCount: tokens.length,
      removedStale: stale.length,
      failures,
      transport: transports[0] ?? "none",
      transports,
      pushEventRecorded: true,
      fromPushEvent: args.fromPushEvent,
      pushEventId: args.pushEventId,
      event: args.event,
      phase: args.phase,
      error: sent > 0
        ? undefined
        : thirdPartyAuth && !isApnsConfigured()
        ? "FCM APNs auth failed (THIRD_PARTY_AUTH_ERROR). Set APNS_AUTH_KEY / APNS_KEY_ID / APNS_TEAM_ID Edge secrets (or upload the .p8 in Firebase Console → Cloud Messaging)."
        : thirdPartyAuth
        ? "FCM APNs auth failed and direct APNs could not send. Rebuild/open the customer app so apns_token is registered."
        : failures[0] ?? "Push send failed for all device tokens.",
      diagnostics: pushConfigReport(),
    },
    { headers: CORS_HEADERS },
  );
}

function humanizeFcmFailure(error: string): string {
  if (/THIRD_PARTY_AUTH_ERROR/i.test(error)) {
    return "THIRD_PARTY_AUTH_ERROR: Firebase cannot authenticate to APNs. Direct APNs fallback needs APNS_* secrets + apns_token on device_tokens.";
  }
  return error;
}

async function notifyDriverApproval(
  admin: ReturnType<typeof createClient>,
  booking: {
    id: string;
    driver_id: string | null;
    vehicle_name?: string | null;
    vehicle_make?: string | null;
    vehicle_model?: string | null;
  },
  event: "driver_pickup_approved" | "driver_return_approved",
  opts: { fromPushEvent: boolean; pushEventId: string | null },
) {
  console.log("[notify-booking-push] notifyDriverApproval:", JSON.stringify({
    bookingId: booking.id,
    recipientUserId: booking.driver_id,
    event,
    fromPushEvent: opts.fromPushEvent,
    pushEventId: opts.pushEventId,
  }));

  if (!booking.driver_id) {
    console.log("[notify-booking-push] driver approval skipped — no driver_id");
    return Response.json(
      { ok: false, skipped: true, error: "Booking has no driver_id." },
      { headers: CORS_HEADERS },
    );
  }

  const vehicle =
    booking.vehicle_name ||
    [booking.vehicle_make, booking.vehicle_model].filter(Boolean).join(" ") ||
    "your EV";
  const title = event === "driver_pickup_approved"
    ? "Customer approved pickup"
    : "Customer approved return";
  const body = event === "driver_pickup_approved"
    ? `You’re cleared to drive ${vehicle}. Live tracking is on.`
    : `Return approved for ${vehicle}. Job complete.`;

  if (!opts.fromPushEvent) {
    console.log(
      "[notify-booking-push] driver approval direct call — insert + send",
      JSON.stringify({ bookingId: booking.id, recipientUserId: booking.driver_id }),
    );
    const insertedId = await insertPushEvent(admin, {
      bookingId: booking.id,
      recipientUserId: booking.driver_id,
      event,
      title,
      body,
    });
    opts = { ...opts, pushEventId: insertedId ?? opts.pushEventId };
  } else if (opts.pushEventId) {
    if (await wasFcmSent(admin, opts.pushEventId)) {
      console.log(
        "[notify-booking-push] driver approval skip — already fcm_sent",
        opts.pushEventId,
      );
      return Response.json(
        {
          ok: true,
          sent: 0,
          skipped: true,
          alreadySent: true,
          event,
          fromPushEvent: true,
        },
        { headers: CORS_HEADERS },
      );
    }
  }

  const pushConfigured = isPushConfigured();
  console.log(
    "[notify-booking-push] driver approval push configured:",
    pushConfigured,
    JSON.stringify(pushConfigReport()),
  );
  if (!pushConfigured) {
    return Response.json(
      {
        ok: true,
        sent: 0,
        skipped: true,
        event,
        note: "push_event_recorded",
        fromPushEvent: opts.fromPushEvent,
      },
      { headers: CORS_HEADERS },
    );
  }

  // Drivers may also have rows in device_tokens keyed by their auth user id.
  const { data: tokens, error: tokensError } = await admin
    .from("device_tokens")
    .select("fcm_token, apns_token")
    .eq("customer_id", booking.driver_id);

  console.log(
    "[notify-booking-push] driver device_tokens query result:",
    JSON.stringify({ tokens, error: tokensError }),
  );
  console.log(
    "[notify-booking-push] driver device token(s) found:",
    (tokens ?? []).length,
    JSON.stringify((tokens ?? []).map((t) => ({
      fcm: t.fcm_token?.slice(0, 12),
      hasApns: !!t.apns_token,
    }))),
  );

  let sent = 0;
  const transports: string[] = [];
  for (const row of tokens ?? []) {
    console.log(
      "[notify-booking-push] driver sendPushToDevice",
      JSON.stringify({
        fcmPrefix: row.fcm_token?.slice(0, 12),
        hasApns: !!row.apns_token,
      }),
    );
    const result = await sendPushToDevice(row, {
      title,
      body,
      data: { booking_id: booking.id, kind: event },
    });
    console.log(
      "[notify-booking-push] full push send response (driver):",
      JSON.stringify(result),
    );
    if (result.ok) {
      sent += 1;
      if (result.transport) transports.push(result.transport);
    }
  }

  if (sent > 0 && opts.pushEventId) {
    await markPushEventFcmSent(admin, opts.pushEventId);
  }

  console.log("[notify-booking-push] driver approval send summary:", { sent, event, transports });
  return Response.json(
    {
      ok: sent > 0 || true,
      sent,
      event,
      transport: transports[0] ?? "none",
      transports,
      fromPushEvent: opts.fromPushEvent,
    },
    { headers: CORS_HEADERS },
  );
}

function notificationCopy(phase: "preTrip" | "postTrip") {
  if (phase === "preTrip") {
    return {
      title: "Pickup update",
      body:
        "Your pre-trip inspection is ready for review. Approve within 15 seconds, or we’ll auto-approve.",
    };
  }
  return {
    title: "Return status",
    body:
      "Quick-look your return photos. Approve within 15 seconds, or we’ll auto-approve.",
  };
}

async function wasFcmSent(
  admin: ReturnType<typeof createClient>,
  pushEventId: string,
): Promise<boolean> {
  try {
    const { data } = await admin
      .from("push_events")
      .select("fcm_sent_at")
      .eq("id", pushEventId)
      .maybeSingle();
    return data?.fcm_sent_at != null;
  } catch {
    return false;
  }
}

async function markPushEventFcmSent(
  admin: ReturnType<typeof createClient>,
  pushEventId: string,
) {
  try {
    await admin
      .from("push_events")
      .update({ fcm_sent_at: new Date().toISOString() })
      .eq("id", pushEventId)
      .is("fcm_sent_at", null);
  } catch {
    // Non-fatal (column may not exist until migration is applied).
  }
}

async function insertPushEvent(
  admin: ReturnType<typeof createClient>,
  args: {
    bookingId: string;
    recipientUserId: string | null;
    event: string;
    title: string;
    body: string;
  },
): Promise<string | null> {
  if (!args.recipientUserId) return null;
  try {
    const { data, error } = await admin
      .from("push_events")
      .insert({
        booking_id: args.bookingId,
        recipient_user_id: args.recipientUserId,
        event: args.event,
        title: args.title,
        body: args.body,
      })
      .select("id")
      .maybeSingle();
    if (error) {
      console.error("[notify-booking-push] insertPushEvent error:", error.message);
      return null;
    }
    return typeof data?.id === "string" ? data.id : null;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("[notify-booking-push] insertPushEvent exception:", message);
    return null;
  }
}

async function loadTokensForCustomer(
  admin: ReturnType<typeof createClient>,
  customerId: string | null,
) {
  console.log("[notify-booking-push] loadTokensForCustomer customerId:", customerId);
  if (!customerId) {
    return [] as Array<{ fcm_token: string; apns_token: string | null }>;
  }

  const { data, error } = await admin
    .from("device_tokens")
    .select("fcm_token, apns_token")
    .eq("customer_id", customerId);

  console.log(
    "[notify-booking-push] device_tokens by customer_id query result:",
    JSON.stringify({ data, error }),
  );

  if (error) throw new Error(error.message);
  let byId = (data ?? []) as Array<{ fcm_token: string; apns_token: string | null }>;
  // Prefer rows that can use direct APNs (FCM alone fails with THIRD_PARTY_AUTH_ERROR).
  const withApns = byId.filter((t) =>
    typeof t.apns_token === "string" && t.apns_token.length >= 32
  );
  if (withApns.length > 0) byId = withApns;
  if (byId.length > 0) {
    console.log(
      "[notify-booking-push] device token(s) found by customer_id:",
      byId.length,
      JSON.stringify(byId.map((t) => ({
        fcm: t.fcm_token?.slice(0, 12),
        hasApns: !!t.apns_token,
      }))),
    );
    return byId;
  }

  console.log(
    "[notify-booking-push] no tokens by customer_id — falling back to email lookup",
  );
  const { data: userData } = await admin.auth.admin.getUserById(customerId);
  const email = (userData?.user?.email ?? "").toLowerCase();
  console.log("[notify-booking-push] auth user email for fallback:", email || "(none)");
  if (!email) return [];

  const { data: byEmail, error: emailError } = await admin
    .from("device_tokens")
    .select("fcm_token, apns_token")
    .eq("customer_email", email);
  console.log(
    "[notify-booking-push] device_tokens by customer_email query result:",
    JSON.stringify({ byEmail, emailError }),
  );
  if (emailError) throw new Error(emailError.message);
  const rows = (byEmail ?? []) as Array<{ fcm_token: string; apns_token: string | null }>;
  console.log(
    "[notify-booking-push] device token(s) found by email:",
    rows.length,
    JSON.stringify(rows.map((t) => ({
      fcm: t.fcm_token?.slice(0, 12),
      hasApns: !!t.apns_token,
    }))),
  );
  return rows;
}

function createAdminClient() {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  }
  return createClient(supabaseUrl, serviceKey);
}

function asUUID(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(trimmed)
    ? trimmed
    : null;
}
