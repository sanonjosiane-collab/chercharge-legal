// Accepts customer registration photo + policy from the iOS app and enqueues
// them for Chercharge Admin (Customers tab). Works for Firebase / local users
// who do not have a Supabase Auth session yet — resolves account by email.
//
// POST JSON:
// {
//   customer_email, customer_name, local_vehicle_id, vehicle_display_name,
//   license_plate, make, model, year, insurance_policy, insurance_company_name,
//   registration_expiration, policy_expiration,
//   registration_photo_base64?, insurance_card_photo_base64?
// }
//
// Auth: apikey (publishable). verify_jwt = false.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { requireClientApiKey } from "../_shared/clientApiKey.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const BUCKET = "customer-vehicle-docs";

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
    const customerEmail = normalizeEmail(body?.customer_email);

    if (!customerEmail || !customerEmail.includes("@")) {
      return Response.json(
        { error: "customer_email is required" },
        { status: 400, headers: CORS_HEADERS },
      );
    }

    // Reject synthetic guest addresses so the admin queue stays meaningful.
    if (customerEmail.endsWith("@chercharge.local")) {
      return Response.json(
        {
          error:
            "Guest accounts cannot submit documents for admin review. Sign in with email and password.",
        },
        { status: 400, headers: CORS_HEADERS },
      );
    }

    const admin = createAdminClient();

    // Status poll for admin decisions (no photo upload).
    // Lookup is by local_vehicle_id (garage id) so email mismatches can't hide approvals.
    if (body?.action === "status") {
      const ids = Array.isArray(body?.local_vehicle_ids)
        ? body.local_vehicle_ids
          .map((v: unknown) => asUUID(v))
          .filter((v: string | null): v is string => !!v)
        : [];

      let rows: Record<string, unknown>[] = [];
      if (ids.length > 0) {
        const { data, error } = await admin
          .from("customer_vehicle_documents")
          .select(
            "id, customer_id, local_vehicle_id, customer_email, status, submitted_at, reviewed_at, reviewer_note",
          )
          .in("local_vehicle_id", ids);
        if (error) {
          return Response.json(
            { error: error.message },
            { status: 400, headers: CORS_HEADERS },
          );
        }
        rows = Array.isArray(data) ? data : [];
      } else if (customerEmail) {
        const { data, error } = await admin
          .from("customer_vehicle_documents")
          .select(
            "id, customer_id, local_vehicle_id, customer_email, status, submitted_at, reviewed_at, reviewer_note",
          )
          .ilike("customer_email", customerEmail);
        if (error) {
          return Response.json(
            { error: error.message },
            { status: 400, headers: CORS_HEADERS },
          );
        }
        rows = Array.isArray(data) ? data : [];
      }

      // Soft email filter when both are present (case-insensitive). Never drop rows with empty email.
      const documents = rows.filter((row) => {
        if (!customerEmail) return true;
        const rowEmail =
          typeof row.customer_email === "string"
            ? row.customer_email.trim().toLowerCase()
            : "";
        return !rowEmail || rowEmail === customerEmail;
      });

      return Response.json({ ok: true, documents }, {
        headers: CORS_HEADERS,
      });
    }

    const customerName =
      typeof body?.customer_name === "string" && body.customer_name.trim()
        ? body.customer_name.trim()
        : customerEmail.split("@")[0] ?? "Customer";
    const localVehicleId = asUUID(body?.local_vehicle_id);
    const insurancePolicy =
      typeof body?.insurance_policy === "string"
        ? body.insurance_policy.trim()
        : "";

    if (!localVehicleId) {
      return Response.json(
        { error: "local_vehicle_id must be a UUID" },
        { status: 400, headers: CORS_HEADERS },
      );
    }
    if (!insurancePolicy && !body?.registration_photo_base64) {
      return Response.json(
        { error: "registration photo or insurance_policy is required" },
        { status: 400, headers: CORS_HEADERS },
      );
    }

    const user = await getOrCreateCustomer(admin, customerEmail, customerName);
    await ensureCustomerProfile(admin, user.id, customerName);

    const vehicleFolder = localVehicleId.toLowerCase();
    const customerFolder = user.id.toLowerCase();

    let registrationPath: string | null = null;
    let registrationFileName: string | null = null;
    let registrationContentType: string | null = null;
    const regBytes = decodeBase64(body?.registration_photo_base64);
    if (regBytes) {
      registrationPath =
        `${customerFolder}/${vehicleFolder}/registration-${crypto.randomUUID()}.jpg`;
      registrationFileName = "registration.jpg";
      registrationContentType = "image/jpeg";
      const { error: uploadError } = await admin.storage
        .from(BUCKET)
        .upload(registrationPath, regBytes, {
          contentType: "image/jpeg",
          upsert: true,
        });
      if (uploadError) {
        return Response.json(
          { error: `Registration photo upload failed: ${uploadError.message}` },
          { status: 400, headers: CORS_HEADERS },
        );
      }
    }

    let insuranceCardPath: string | null = null;
    const cardBytes = decodeBase64(body?.insurance_card_photo_base64);
    if (cardBytes) {
      insuranceCardPath =
        `${customerFolder}/${vehicleFolder}/insurance-card-${crypto.randomUUID()}.jpg`;
      const { error: cardError } = await admin.storage
        .from(BUCKET)
        .upload(insuranceCardPath, cardBytes, {
          contentType: "image/jpeg",
          upsert: true,
        });
      if (cardError) {
        return Response.json(
          { error: `Insurance card upload failed: ${cardError.message}` },
          { status: 400, headers: CORS_HEADERS },
        );
      }
    }

    let priorityScore = 100;
    if (registrationPath) priorityScore += 50;
    if (insurancePolicy) priorityScore += 50;
    if (insuranceCardPath) priorityScore += 10;

    const vehicleDisplayName =
      typeof body?.vehicle_display_name === "string" &&
        body.vehicle_display_name.trim()
        ? body.vehicle_display_name.trim()
        : "Vehicle";

    // Preserve admin Approve/Reject unless the customer uploaded new document bytes
    // (a true resubmit after rejection / document change).
    const { data: existingRow } = await admin
      .from("customer_vehicle_documents")
      .select(
        "id, status, registration_storage_path, registration_file_name, registration_content_type, insurance_card_storage_path, reviewed_at, reviewer_note, submitted_at, priority_score",
      )
      .eq("customer_id", user.id)
      .eq("local_vehicle_id", localVehicleId)
      .maybeSingle();

    const alreadyReviewed =
      existingRow?.status === "approved" || existingRow?.status === "rejected";
    const uploadingNewDocs = !!(regBytes || cardBytes);

    if (alreadyReviewed && !uploadingNewDocs) {
      return Response.json(
        {
          ok: true,
          document: {
            id: existingRow.id,
            customer_id: user.id,
            local_vehicle_id: localVehicleId,
            status: existingRow.status,
            priority_score: existingRow.priority_score ?? priorityScore,
            submitted_at: existingRow.submitted_at,
          },
          message: "Already reviewed — status preserved.",
        },
        { headers: CORS_HEADERS },
      );
    }

    const row = {
      customer_id: user.id,
      local_vehicle_id: localVehicleId,
      customer_name: customerName,
      customer_email: customerEmail,
      vehicle_display_name: vehicleDisplayName,
      license_plate: asOptionalString(body?.license_plate),
      make: asOptionalString(body?.make),
      model: asOptionalString(body?.model),
      year: typeof body?.year === "number" ? body.year : null,
      insurance_policy: insurancePolicy,
      insurance_company_name: asOptionalString(body?.insurance_company_name),
      registration_expiration: asOptionalString(body?.registration_expiration),
      policy_expiration: asOptionalString(body?.policy_expiration),
      registration_storage_path:
        registrationPath ?? existingRow?.registration_storage_path ?? null,
      registration_file_name:
        registrationFileName ?? existingRow?.registration_file_name ?? null,
      registration_content_type:
        registrationContentType ?? existingRow?.registration_content_type ?? null,
      insurance_card_storage_path:
        insuranceCardPath ?? existingRow?.insurance_card_storage_path ?? null,
      status: "pendingReview",
      priority_score: priorityScore,
      submitted_at: new Date().toISOString(),
      reviewed_at: null,
      reviewer_note: null,
      reviewed_by: null,
    };

    const { data, error } = await admin
      .from("customer_vehicle_documents")
      .upsert(row, { onConflict: "customer_id,local_vehicle_id" })
      .select("id, customer_id, local_vehicle_id, status, priority_score, submitted_at")
      .single();

    if (error) {
      return Response.json(
        { error: error.message },
        { status: 400, headers: CORS_HEADERS },
      );
    }

    return Response.json(
      {
        ok: true,
        document: data,
        message: "Queued for Chercharge Admin (Customers tab).",
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

  for (let page = 1; page <= 25; page++) {
    const listed = await admin.auth.admin.listUsers({ page, perPage: 200 });
    if (listed.error) throw new Error(listed.error.message);
    const found = listed.data.users.find(
      (u) => (u.email ?? "").toLowerCase() === email,
    );
    if (found) return found;
    if (listed.data.users.length < 200) break;
  }

  throw new Error("Could not resolve customer account for document review.");
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
    // Never demote an admin.
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

function asOptionalString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed ? trimmed : null;
}

function decodeBase64(value: unknown): Uint8Array | null {
  if (typeof value !== "string" || !value.trim()) return null;
  let raw = value.trim();
  const comma = raw.indexOf(",");
  if (raw.startsWith("data:") && comma >= 0) {
    raw = raw.slice(comma + 1);
  }
  try {
    const binary = atob(raw);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytes.length > 0 ? bytes : null;
  } catch {
    return null;
  }
}
