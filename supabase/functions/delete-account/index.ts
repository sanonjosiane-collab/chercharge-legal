// Deletes the authenticated Supabase Auth user (and cascaded profile rows).
// POST {} — requires Supabase Auth JWT. Service role performs the delete.
// verify_jwt = true

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { supabaseClientKey } from "../_shared/clientApiKey.ts";

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
    const user = await requireUser(req);
    const admin = createAdminClient();

    const { error } = await admin.auth.admin.deleteUser(user.id);
    if (error) {
      return Response.json(
        { error: error.message },
        { status: 400, headers: CORS_HEADERS },
      );
    }

    return Response.json(
      { deleted: true, userId: user.id },
      { headers: CORS_HEADERS },
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    const status = message === "Unauthorized" ? 401 : 500;
    return Response.json({ error: message }, { status, headers: CORS_HEADERS });
  }
});

function createAdminClient() {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    throw new Error("Missing Supabase env");
  }
  return createClient(supabaseUrl, serviceKey);
}

async function requireUser(req: Request) {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    throw new Error("Unauthorized");
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const clientKey = supabaseClientKey();
  if (!supabaseUrl || !clientKey) {
    throw new Error("Missing Supabase env");
  }

  const token = authHeader.replace("Bearer ", "");
  const client = createClient(supabaseUrl, clientKey);
  const { data, error } = await client.auth.getUser(token);
  if (error || !data.user) {
    throw new Error("Unauthorized");
  }
  return data.user;
}
