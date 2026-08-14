// Waits until the booking's stored approval deadline, then auto-approves.
// Invoked by DB trigger when customer_approval_deadline / return_approval_deadline is set.
// Keeps the backend as source of truth even if customer + driver apps are closed.
//
// POST JSON: { booking_id, phase?: "pickup"|"return", deadline?: ISO string }
// Auth: service role (or publishable + internal).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

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
    const body = await req.json();
    const bookingId = typeof body?.booking_id === "string" ? body.booking_id : null;
    if (!bookingId || !/^[0-9a-f-]{36}$/i.test(bookingId)) {
      return Response.json(
        { error: "booking_id must be a UUID" },
        { status: 400, headers: CORS_HEADERS },
      );
    }

    const admin = createAdminClient();
    const { data: booking, error: readError } = await admin
      .from("bookings")
      .select(
        "id, status, driver_id, customer_approval_deadline, return_approval_deadline, customer_approved_pickup_at, customer_approved_return_at, pre_trip_inspection, post_trip_inspection",
      )
      .eq("id", bookingId)
      .maybeSingle();

    if (readError) {
      return Response.json(
        { error: readError.message },
        { status: 400, headers: CORS_HEADERS },
      );
    }
    if (!booking) {
      return Response.json(
        { error: "Booking not found" },
        { status: 404, headers: CORS_HEADERS },
      );
    }

    const deadlineIso =
      (typeof body?.deadline === "string" && body.deadline) ||
      booking.customer_approval_deadline ||
      booking.return_approval_deadline;
    const deadlineMs = deadlineIso ? Date.parse(deadlineIso) : NaN;
    if (Number.isFinite(deadlineMs)) {
      const waitMs = Math.min(
        Math.max(deadlineMs - Date.now() + 750, 0),
        30_000, // hard cap so the isolate cannot hang forever
      );
      if (waitMs > 0) {
        await new Promise((resolve) => setTimeout(resolve, waitMs));
      }
    } else {
      // Fallback: classic 15s window from invoke time.
      await new Promise((resolve) => setTimeout(resolve, 15_750));
    }

    const { data: rows, error } = await admin.rpc("auto_approve_due_booking", {
      p_booking_id: bookingId,
    });
    if (error) {
      return Response.json(
        { error: error.message },
        { status: 400, headers: CORS_HEADERS },
      );
    }

    const row = Array.isArray(rows) ? rows[0] : rows;
    const approved = row?.approved === true;
    const action = typeof row?.action === "string" ? row.action : "not_due";
    const newStatus = typeof row?.new_status === "string"
      ? row.new_status
      : booking.status;

    if (approved && booking.driver_id) {
      const notifyEvent = action === "approve_pickup"
        ? "driver_pickup_approved"
        : "driver_return_approved";
      try {
        const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
        const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
        if (supabaseUrl && serviceKey) {
          await fetch(`${supabaseUrl}/functions/v1/notify-booking-push`, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${serviceKey}`,
              apikey: serviceKey,
            },
            body: JSON.stringify({
              booking_id: bookingId,
              event: notifyEvent,
            }),
          });
        }
      } catch (notifyError) {
        console.error("[schedule-auto-approve] notify failed:", notifyError);
      }
    }

    return Response.json(
      {
        ok: true,
        approved,
        action,
        status: newStatus,
        auto: true,
        waited_until: deadlineIso ?? null,
      },
      { headers: CORS_HEADERS },
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return Response.json(
      { error: message },
      { status: 500, headers: CORS_HEADERS },
    );
  }
});

function createAdminClient() {
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
