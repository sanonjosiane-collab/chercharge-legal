// Auto-advances a booking through demo statuses so Tracking works without a driver app.
// Invoke after creating a booking: POST { "booking_id": "<uuid>" }

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const STATUSES = [
  "driverEnRoute",
  "driverArrived",
  // Pauses here for pre-trip inspection + customer Approve pickup (client-driven).
  // After approval the client continues: pickedUp → charging → returning → awaitingPostTripInspection.
] as const;

const DELAY_MS = 3000;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers":
          "authorization, x-client-info, apikey, content-type",
      },
    });
  }

  try {
    const { booking_id } = await req.json();
    if (!booking_id || typeof booking_id !== "string") {
      return Response.json({ error: "booking_id required" }, { status: 400 });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceKey) {
      return Response.json({ error: "Missing Supabase env" }, { status: 500 });
    }

    const admin = createClient(supabaseUrl, serviceKey);

    // Respond immediately; advance in background so the client isn't blocked.
    // deno-lint-ignore no-explicit-any
    const runtime = globalThis as any;
    if (runtime.EdgeRuntime?.waitUntil) {
      runtime.EdgeRuntime.waitUntil(advanceBooking(admin, booking_id));
    } else {
      // Local/dev fallback: still kick off without blocking the response forever.
      advanceBooking(admin, booking_id);
    }

    return Response.json({ ok: true, booking_id });
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : "Unknown error" },
      { status: 500 },
    );
  }
});

async function advanceBooking(
  admin: ReturnType<typeof createClient>,
  bookingId: string,
) {
  for (const status of STATUSES) {
    await new Promise((resolve) => setTimeout(resolve, DELAY_MS));
    const { error } = await admin
      .from("bookings")
      .update({ status })
      .eq("id", bookingId);
    if (error) {
      console.error("Failed to advance booking", bookingId, status, error);
      return;
    }
  }
}
