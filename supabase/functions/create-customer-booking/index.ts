// Creates an open `bookings` row for the driver marketplace from the customer app.
// Works for Firebase / local users (no Supabase JWT) — resolves account by email.
//
// POST JSON:
// {
//   customer_email, customer_name?,
//   local_vehicle_id, vehicle_name, vehicle_make, vehicle_model, vehicle_year, vehicle_plate,
//   current_charge_percent, target_charge_percent,
//   pickup_name, pickup_address, pickup_lat, pickup_lng,
//   station_name, station_address, station_lat, station_lng,
//   estimated_price, estimated_minutes,
//   payment_intent_id?
// }
//
// Status poll:
// { action: "status", customer_email, booking_id }
//   → includes inspections + customer_approval_deadline / return_approval_deadline
//   → notifications[] (normalized push_events) + inspection_ready bool
//   → also runs auto_approve_due_booking for this id (server source of truth)
//
// Notifications inbox:
// { action: "notifications", customer_email, booking_id? }
//   → notifications[], inspection_ready, inspection (first unread inspection_ready)
//
// Customer approval:
// { action: "approve_pickup" | "approve_return", customer_email, booking_id }
//   → sets pickup_approval_method / return_approval_method = "manual"
//
// Server auto-approve:
// { action: "auto_approve_due", booking_id }
// { action: "auto_approve_expired" }  // sweep all due bookings
//
// Auth: apikey (publishable). verify_jwt = false.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { requireClientApiKey } from "../_shared/clientApiKey.ts";

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

  const unauthorized = requireClientApiKey(req, CORS_HEADERS);
  if (unauthorized) return unauthorized;

  try {
    const body = await req.json();
    const admin = createAdminClient();

    // Driver/customer timer: auto-approve after the 15s window (no email required).
    if (body?.action === "auto_approve_due") {
      const bookingId = asUUID(body?.booking_id);
      if (!bookingId) {
        return Response.json(
          { error: "booking_id must be a UUID" },
          { status: 400, headers: CORS_HEADERS },
        );
      }

      const { data: before } = await admin
        .from("bookings")
        .select("id, status, driver_id")
        .eq("id", bookingId)
        .maybeSingle();
      if (!before) {
        return Response.json(
          { error: "Booking not found" },
          { status: 404, headers: CORS_HEADERS },
        );
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
      const newStatus =
        typeof row?.new_status === "string" ? row.new_status : before.status;

      if (approved && before.driver_id) {
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
          console.error(
            "[create-customer-booking] auto-approve notify failed:",
            notifyError,
          );
        }
      }

      return Response.json(
        { ok: true, approved, action, status: newStatus, auto: true },
        { headers: CORS_HEADERS },
      );
    }

    // Periodic / ops sweep: approve every booking whose stored deadline has passed.
    if (body?.action === "auto_approve_expired") {
      const { data: rows, error } = await admin.rpc(
        "auto_approve_expired_bookings",
      );
      if (error) {
        return Response.json(
          { error: error.message },
          { status: 400, headers: CORS_HEADERS },
        );
      }
      const list = Array.isArray(rows) ? rows : rows ? [rows] : [];
      const approvedRows = list.filter((r) => r?.approved === true);
      for (const row of approvedRows) {
        const bookingId = row?.booking_id;
        if (!bookingId) continue;
        const notifyEvent = row?.action === "approve_pickup"
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
          console.error(
            "[create-customer-booking] expired sweep notify failed:",
            notifyError,
          );
        }
      }
      return Response.json(
        {
          ok: true,
          checked: list.length,
          approved: approvedRows.length,
          results: list,
        },
        { headers: CORS_HEADERS },
      );
    }

    const customerEmail = normalizeEmail(body?.customer_email);

    if (!customerEmail || !customerEmail.includes("@")) {
      return Response.json(
        { error: "customer_email is required" },
        { status: 400, headers: CORS_HEADERS },
      );
    }

    if (customerEmail.endsWith("@chercharge.local")) {
      return Response.json(
        {
          error:
            "Guest accounts cannot dispatch bookings to drivers. Sign in with email and password.",
        },
        { status: 400, headers: CORS_HEADERS },
      );
    }

    if (body?.action === "status") {
      const bookingId = asUUID(body?.booking_id);
      if (!bookingId) {
        return Response.json(
          { error: "booking_id must be a UUID" },
          { status: 400, headers: CORS_HEADERS },
        );
      }

      const ownership = await assertBookingOwnedByEmail(
        admin,
        bookingId,
        customerEmail,
      );
      if (!ownership.ok) {
        return Response.json(
          { error: ownership.error },
          { status: ownership.status, headers: CORS_HEADERS },
        );
      }

      // Unblock driver even if customer/driver timers never ran (app suspended).
      try {
        const { data: autoRows } = await admin.rpc("auto_approve_due_booking", {
          p_booking_id: bookingId,
        });
        const autoRow = Array.isArray(autoRows) ? autoRows[0] : autoRows;
        // #region agent log
        fetch("http://127.0.0.1:7868/ingest/418cc6ba-2ec5-4f6d-aca9-699e1054421b", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-Debug-Session-Id": "0dc641",
          },
          body: JSON.stringify({
            sessionId: "0dc641",
            runId: "pre-fix",
            hypothesisId: "B",
            location: "create-customer-booking:status",
            message: "status poll auto-approve attempt",
            data: {
              bookingId,
              approved: autoRow?.approved === true,
              action: autoRow?.action ?? null,
              newStatus: autoRow?.new_status ?? null,
            },
            timestamp: Date.now(),
          }),
        }).catch(() => {});
        // #endregion
      } catch {
        // non-fatal
      }

      // Prefer full row (deadlines + approval method). Fall back if migration not applied yet.
      let { data, error } = await admin
        .from("bookings")
        .select(
          "id, status, driver_id, customer_name, vehicle_name, created_at, updated_at, pre_trip_inspection, post_trip_inspection, customer_approved_pickup_at, customer_approved_return_at, customer_approval_deadline, return_approval_deadline, pickup_approval_method, return_approval_method, customer_id",
        )
        .eq("id", bookingId)
        .maybeSingle();

      if (error && /customer_approval_deadline|pickup_approval_method|return_approval/i.test(error.message)) {
        ({ data, error } = await admin
          .from("bookings")
          .select(
            "id, status, driver_id, customer_name, vehicle_name, created_at, updated_at, pre_trip_inspection, post_trip_inspection, customer_approved_pickup_at, customer_approved_return_at, customer_id",
          )
          .eq("id", bookingId)
          .maybeSingle());
      }

      if (error) {
        return Response.json(
          { error: error.message },
          { status: 400, headers: CORS_HEADERS },
        );
      }
      if (!data) {
        return Response.json(
          { error: "Booking not found" },
          { status: 404, headers: CORS_HEADERS },
        );
      }

      // Prefer unread inspection-ready events so local banners still fire when
      // the customer app resumes (remote APNs may have been missed).
      const notifications = await loadBookingNotifications(admin, {
        bookingId,
        customerId: data.customer_id ?? null,
      });
      const unreadInspection = notifications.find(
        (n) =>
          n.type === "inspection_ready" &&
          n.booking_id === bookingId &&
          n.read_at == null,
      );
      const unreadAny = unreadInspection ??
        notifications.find((n) => n.read_at == null) ??
        null;
      const pendingPush = unreadAny
        ? {
          id: unreadAny.id,
          event: unreadAny.event,
          title: unreadAny.title,
          body: unreadAny.body,
          created_at: unreadAny.created_at,
          delivered_at: unreadAny.read_at,
        }
        : null;

      // #region agent log
      fetch("http://127.0.0.1:7868/ingest/418cc6ba-2ec5-4f6d-aca9-699e1054421b", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Debug-Session-Id": "0dc641",
        },
        body: JSON.stringify({
          sessionId: "0dc641",
          runId: "pre-fix",
          hypothesisId: "E",
          location: "create-customer-booking:status",
          message: "status notifications",
          data: {
            bookingId,
            status: data.status,
            notificationCount: notifications.length,
            unreadInspection: unreadInspection != null,
            pendingEvent: pendingPush?.event ?? null,
          },
          timestamp: Date.now(),
        }),
      }).catch(() => {});
      // #endregion

      return Response.json({
        ok: true,
        booking: data,
        notifications,
        pending_push: pendingPush,
        inspection_ready: unreadInspection != null,
      }, {
        headers: CORS_HEADERS,
      });
    }

    // Customer inbox poll: unread (and recent) notifications for this account.
    if (body?.action === "notifications") {
      const bookingId = asUUID(body?.booking_id); // optional filter

      if (bookingId) {
        const ownership = await assertBookingOwnedByEmail(
          admin,
          bookingId,
          customerEmail,
        );
        if (!ownership.ok) {
          return Response.json(
            { error: ownership.error },
            { status: ownership.status, headers: CORS_HEADERS },
          );
        }
      }

      const notifications = await loadCustomerNotifications(admin, {
        customerEmail,
        bookingId,
      });
      const inspection = notifications.find(
        (n) =>
          n.type === "inspection_ready" &&
          (bookingId == null || n.booking_id === bookingId) &&
          n.read_at == null,
      );

      return Response.json({
        ok: true,
        notifications,
        inspection_ready: inspection != null,
        inspection: inspection ?? null,
      }, {
        headers: CORS_HEADERS,
      });
    }

    if (body?.action === "acknowledge_push") {
      const bookingId = asUUID(body?.booking_id);
      const pushEventId = asUUID(body?.push_event_id);
      if (!bookingId || !pushEventId) {
        return Response.json(
          { error: "booking_id and push_event_id must be UUIDs" },
          { status: 400, headers: CORS_HEADERS },
        );
      }
      const ownership = await assertBookingOwnedByEmail(
        admin,
        bookingId,
        customerEmail,
      );
      if (!ownership.ok) {
        return Response.json(
          { error: ownership.error },
          { status: ownership.status, headers: CORS_HEADERS },
        );
      }
      await admin
        .from("push_events")
        .update({ delivered_at: new Date().toISOString() })
        .eq("id", pushEventId)
        .eq("booking_id", bookingId)
        .is("delivered_at", null);
      return Response.json({ ok: true }, { headers: CORS_HEADERS });
    }

    if (
      body?.action === "approve_pickup" || body?.action === "approve_return"
    ) {
      const bookingId = asUUID(body?.booking_id);
      if (!bookingId) {
        return Response.json(
          { error: "booking_id must be a UUID" },
          { status: 400, headers: CORS_HEADERS },
        );
      }

      const ownership = await assertBookingOwnedByEmail(
        admin,
        bookingId,
        customerEmail,
      );
      if (!ownership.ok) {
        return Response.json(
          { error: ownership.error },
          { status: ownership.status, headers: CORS_HEADERS },
        );
      }

      const isPickup = body.action === "approve_pickup";
      const nextStatus = isPickup ? "pickedUp" : "delivered";
      const now = new Date().toISOString();
      const patch: Record<string, unknown> = {
        status: nextStatus,
      };
      if (isPickup) {
        patch.customer_approved_pickup_at = now;
        patch.customer_approval_deadline = null;
        patch.pickup_approval_method = "manual";
      } else {
        patch.customer_approved_return_at = now;
        patch.return_approval_deadline = null;
        patch.return_approval_method = "manual";
      }

      const { data: current, error: readError } = await admin
        .from("bookings")
        .select("id, status, post_trip_inspection")
        .eq("id", bookingId)
        .maybeSingle();
      if (readError) {
        return Response.json(
          { error: readError.message },
          { status: 400, headers: CORS_HEADERS },
        );
      }
      if (!current) {
        return Response.json(
          { error: "Booking not found" },
          { status: 404, headers: CORS_HEADERS },
        );
      }

      // Return-ready trips often stay on awaitingPostTripInspection in the DB.
      const returnReady =
        current.status === "awaitingReturnApproval" ||
        (current.status === "awaitingPostTripInspection" &&
          current.post_trip_inspection != null);
      const wasAwaiting = isPickup
        ? current.status === "awaitingCustomerApproval"
        : returnReady;
      // Idempotent if already advanced; reject wrong-state approvals.
      if (!wasAwaiting && current.status !== nextStatus) {
        return Response.json(
          {
            error:
              `Cannot approve while booking is ${current.status}. Expected ${
                isPickup
                  ? "awaitingCustomerApproval"
                  : "awaitingReturnApproval|awaitingPostTripInspection"
              }.`,
          },
          { status: 409, headers: CORS_HEADERS },
        );
      }

      const { data, error } = await admin
        .from("bookings")
        .update(patch)
        .eq("id", bookingId)
        .select(
          "id, status, customer_approved_pickup_at, customer_approved_return_at, driver_id",
        )
        .maybeSingle();
      if (error) {
        return Response.json(
          { error: error.message },
          { status: 400, headers: CORS_HEADERS },
        );
      }

      // Wake the driver app when the customer approves (best-effort).
      if (data?.driver_id && wasAwaiting) {
        const notifyEvent = isPickup
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
          console.error(
            "[create-customer-booking] driver notify failed:",
            notifyError,
          );
        }
      }

      return Response.json({ ok: true, booking: data }, {
        headers: CORS_HEADERS,
      });
    }

    const customerName =
      typeof body?.customer_name === "string" && body.customer_name.trim()
        ? body.customer_name.trim()
        : customerEmail.split("@")[0] ?? "Customer";

    const localVehicleId = asUUID(body?.local_vehicle_id);
    if (!localVehicleId) {
      return Response.json(
        { error: "local_vehicle_id must be a UUID" },
        { status: 400, headers: CORS_HEADERS },
      );
    }

    const pickupLat = asNumber(body?.pickup_lat);
    const pickupLng = asNumber(body?.pickup_lng);
    const stationLat = asNumber(body?.station_lat);
    const stationLng = asNumber(body?.station_lng);
    const targetCharge = asInt(body?.target_charge_percent);
    const startingCharge = asInt(body?.current_charge_percent) ?? 0;
    const estimatedPrice = asNumber(body?.estimated_price);
    const estimatedMinutes = asInt(body?.estimated_minutes);

    const pickupName = asRequiredString(body?.pickup_name, "Pickup");
    const pickupAddress = asRequiredString(body?.pickup_address, "Address");
    const stationName = asRequiredString(body?.station_name, "Station");
    const stationAddress = asRequiredString(
      body?.station_address,
      "Station address",
    );

    if (
      pickupLat == null ||
      pickupLng == null ||
      stationLat == null ||
      stationLng == null ||
      targetCharge == null ||
      estimatedPrice == null ||
      estimatedMinutes == null
    ) {
      return Response.json(
        {
          error:
            "pickup/station coordinates, target_charge_percent, estimated_price, and estimated_minutes are required",
        },
        { status: 400, headers: CORS_HEADERS },
      );
    }

    const user = await getOrCreateCustomer(admin, customerEmail, customerName);
    await ensureCustomerProfile(admin, user.id, customerName);

    const vehicleName = asRequiredString(body?.vehicle_name, "EV");
    const vehicleMake = asRequiredString(body?.vehicle_make, "Tesla");
    const vehicleModel = asRequiredString(body?.vehicle_model, "Model 3");
    const vehicleYear = asInt(body?.vehicle_year) ?? 2024;
    const vehiclePlate = asRequiredString(body?.vehicle_plate, "—");
    const smokingInVehicle = body?.smoking_in_vehicle === true ||
      body?.smoking_in_vehicle === "true" ||
      body?.smoking_in_vehicle === 1;

    const { error: vehicleError } = await admin.from("vehicles").upsert(
      {
        id: localVehicleId,
        owner_id: user.id,
        name: vehicleName,
        make: vehicleMake,
        model: vehicleModel,
        license_plate: vehiclePlate,
        current_charge_percent: Math.min(100, Math.max(0, startingCharge)),
      },
      { onConflict: "id" },
    );
    if (vehicleError) {
      return Response.json(
        { error: `Vehicle sync failed: ${vehicleError.message}` },
        { status: 400, headers: CORS_HEADERS },
      );
    }

    const insertBase: Record<string, unknown> = {
      customer_id: user.id,
      vehicle_id: localVehicleId,
      status: "requested",
      pickup_name: pickupName,
      pickup_address: pickupAddress,
      pickup_lat: pickupLat,
      pickup_lng: pickupLng,
      station_name: stationName,
      station_address: stationAddress,
      station_lat: stationLat,
      station_lng: stationLng,
      target_charge_percent: Math.min(100, Math.max(0, targetCharge)),
      starting_charge_percent: Math.min(100, Math.max(0, startingCharge)),
      estimated_price: estimatedPrice,
      estimated_minutes: estimatedMinutes,
      customer_name: customerName,
      vehicle_name: vehicleName,
      vehicle_make: vehicleMake,
      vehicle_model: vehicleModel,
      vehicle_year: vehicleYear,
      vehicle_plate: vehiclePlate,
      smoking_in_vehicle: smokingInVehicle,
    };

    let { data, error } = await admin
      .from("bookings")
      .insert(insertBase)
      .select(
        "id, status, customer_id, vehicle_id, customer_name, vehicle_name, vehicle_make, vehicle_model, vehicle_plate, smoking_in_vehicle, created_at",
      )
      .single();

    if (error && /smoking_in_vehicle/i.test(error.message)) {
      const { smoking_in_vehicle: _omit, ...withoutSmoking } = insertBase;
      ({ data, error } = await admin
        .from("bookings")
        .insert(withoutSmoking)
        .select(
          "id, status, customer_id, vehicle_id, customer_name, vehicle_name, vehicle_make, vehicle_model, vehicle_plate, created_at",
        )
        .single());
    }

    if (error) {
      return Response.json(
        { error: error.message },
        { status: 400, headers: CORS_HEADERS },
      );
    }

    return Response.json(
      {
        ok: true,
        booking: data,
        message: "Booking sent to driver open jobs.",
      },
      { headers: CORS_HEADERS },
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return Response.json(
      { error: message },
      { status: 500, headers: CORS_HEADERS },
    );
  }
});

function createAdminClient() {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  }
  return createClient(supabaseUrl, serviceKey);
}

async function getOrCreateCustomer(
  admin: ReturnType<typeof createClient>,
  email: string,
  fullName: string,
) {
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
    user_metadata: { full_name: fullName },
  });
  if (created.data.user) return created.data.user;

  const message = created.error?.message?.toLowerCase() ?? "";
  const alreadyExists =
    message.includes("already") ||
    message.includes("registered") ||
    message.includes("exists");

  if (!alreadyExists && created.error) {
    throw new Error(created.error.message);
  }

  const found = await findCustomerByEmail(admin, email);
  if (found) return found;
  throw new Error("Could not resolve customer account for booking dispatch.");
}

async function findCustomerByEmail(
  admin: ReturnType<typeof createClient>,
  email: string,
) {
  for (let page = 1; page <= 25; page++) {
    const listed = await admin.auth.admin.listUsers({ page, perPage: 200 });
    if (listed.error) throw new Error(listed.error.message);
    const found = listed.data.users.find(
      (u) => (u.email ?? "").toLowerCase() === email,
    );
    if (found) return found;
    if (listed.data.users.length < 200) break;
  }
  return null;
}

async function assertBookingOwnedByEmail(
  admin: ReturnType<typeof createClient>,
  bookingId: string,
  customerEmail: string,
): Promise<
  | { ok: true }
  | { ok: false; error: string; status: number }
> {
  const user = await findCustomerByEmail(admin, customerEmail);
  if (!user) {
    // Soft allow when Auth user can't be resolved — client created the booking with this email.
    return { ok: true };
  }
  const { data: bookingOwner, error } = await admin
    .from("bookings")
    .select("customer_id")
    .eq("id", bookingId)
    .maybeSingle();
  if (error) {
    return { ok: false, error: error.message, status: 400 };
  }
  if (!bookingOwner) {
    return { ok: false, error: "Booking not found", status: 404 };
  }
  if (
    bookingOwner.customer_id &&
    bookingOwner.customer_id !== user.id
  ) {
    return { ok: false, error: "Booking not found", status: 404 };
  }
  return { ok: true };
}

async function ensureCustomerProfile(
  admin: ReturnType<typeof createClient>,
  userId: string,
  fullName: string,
) {
  const existing = await admin
    .from("profiles")
    .select("id, role")
    .eq("id", userId)
    .maybeSingle();

  if (existing.data) {
    await admin
      .from("profiles")
      .update({ full_name: fullName })
      .eq("id", userId);
    return;
  }

  const inserted = await admin.from("profiles").insert({
    id: userId,
    full_name: fullName,
    role: "customer",
  });
  if (inserted.error) {
    throw new Error(inserted.error.message);
  }
}

function normalizeEmail(value: unknown): string {
  if (typeof value !== "string") return "";
  return value.trim().toLowerCase();
}

function asUUID(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(trimmed)
    ? trimmed
    : null;
}

function asRequiredString(value: unknown, fallback: string): string {
  if (typeof value === "string" && value.trim()) return value.trim();
  return fallback;
}

function asNumber(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim()) {
    const n = Number(value);
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

function asInt(value: unknown): number | null {
  const n = asNumber(value);
  return n == null ? null : Math.round(n);
}

type NormalizedNotification = {
  id: string;
  type: string;
  event: string;
  booking_id: string;
  title: string | null;
  body: string | null;
  phase: "preTrip" | "postTrip" | null;
  read_at: string | null;
  created_at: string | null;
};

function normalizePushEvent(row: Record<string, unknown>): NormalizedNotification {
  const event = typeof row.event === "string" ? row.event : "";
  let type = event;
  let phase: "preTrip" | "postTrip" | null = null;
  if (event === "inspection_ready_preTrip") {
    type = "inspection_ready";
    phase = "preTrip";
  } else if (event === "inspection_ready_postTrip") {
    type = "inspection_ready";
    phase = "postTrip";
  } else if (event === "driver_arrived") {
    type = "driver_arrived";
  } else if (event === "driver_en_route") {
    type = "driver_en_route";
  }

  return {
    id: String(row.id ?? ""),
    type,
    event,
    booking_id: String(row.booking_id ?? ""),
    title: typeof row.title === "string" ? row.title : null,
    body: typeof row.body === "string" ? row.body : null,
    phase,
    read_at: typeof row.delivered_at === "string" ? row.delivered_at : null,
    created_at: typeof row.created_at === "string" ? row.created_at : null,
  };
}

async function loadBookingNotifications(
  admin: ReturnType<typeof createClient>,
  opts: { bookingId: string; customerId: string | null },
): Promise<NormalizedNotification[]> {
  let query = admin
    .from("push_events")
    .select("id, booking_id, event, title, body, created_at, delivered_at")
    .eq("booking_id", opts.bookingId)
    .in("event", [
      "inspection_ready_preTrip",
      "inspection_ready_postTrip",
      "driver_arrived",
      "driver_en_route",
      "driver_pickup_approved",
      "driver_return_approved",
    ])
    .order("created_at", { ascending: false })
    .limit(20);

  if (opts.customerId) {
    query = query.eq("recipient_user_id", opts.customerId);
  }

  const { data } = await query;
  if (!Array.isArray(data)) return [];
  return data.map((row) => normalizePushEvent(row as Record<string, unknown>));
}

async function loadCustomerNotifications(
  admin: ReturnType<typeof createClient>,
  opts: {
    customerEmail: string;
    bookingId: string | null;
  },
): Promise<NormalizedNotification[]> {
  const user = await findCustomerByEmail(admin, opts.customerEmail);

  if (opts.bookingId) {
    return loadBookingNotifications(admin, {
      bookingId: opts.bookingId,
      customerId: user?.id ?? null,
    });
  }

  if (!user) return [];

  const { data } = await admin
    .from("push_events")
    .select("id, booking_id, event, title, body, created_at, delivered_at")
    .eq("recipient_user_id", user.id)
    .in("event", [
      "inspection_ready_preTrip",
      "inspection_ready_postTrip",
      "driver_arrived",
      "driver_en_route",
    ])
    .order("created_at", { ascending: false })
    .limit(40);

  if (!Array.isArray(data)) return [];
  return data.map((row) => normalizePushEvent(row as Record<string, unknown>));
}
