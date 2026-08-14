// Exchanges a Tesla OAuth authorization code (or refresh_token) for Fleet API tokens.
// Also builds the authorize URL from server secrets so the iOS app never embeds
// TESLA_CLIENT_ID / TESLA_CLIENT_SECRET.
//
// POST { "action": "authorize_url", "state": "..." }
//   → { authorize_url, redirect_uri, audience }  (never returns client_secret)
// POST { "code": "..." } or { "refresh_token": "..." }
//   → access/refresh tokens
//
// Secrets (Supabase): TESLA_CLIENT_ID, TESLA_CLIENT_SECRET, TESLA_REDIRECT_URI, TESLA_AUDIENCE
// Auth: apikey header (sb_publishable_… or legacy anon). verify_jwt is off for new keys.

import { requireClientApiKey } from "../_shared/clientApiKey.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const TOKEN_URL = "https://fleet-auth.prd.vn.cloud.tesla.com/oauth2/v3/token";
const AUTHORIZE_URL = "https://auth.tesla.com/oauth2/v3/authorize";
const DEFAULT_SCOPES = "openid offline_access user_data vehicle_device_data";
const DEFAULT_AUDIENCE = "https://fleet-api.prd.na.vn.cloud.tesla.com";
const DEFAULT_REDIRECT_URI =
  "https://kjzbiiechaiodwdxstfz.supabase.co/functions/v1/tesla-oauth-callback";

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
    const clientId = Deno.env.get("TESLA_CLIENT_ID");
    const clientSecret = Deno.env.get("TESLA_CLIENT_SECRET");
    const redirectUri = Deno.env.get("TESLA_REDIRECT_URI") ?? DEFAULT_REDIRECT_URI;
    const audience = Deno.env.get("TESLA_AUDIENCE") ?? DEFAULT_AUDIENCE;

    if (!clientId || !clientSecret) {
      return Response.json(
        {
          error: "Missing TESLA_CLIENT_ID or TESLA_CLIENT_SECRET",
        },
        { status: 500, headers: CORS_HEADERS },
      );
    }

    const body = await req.json();

    // App asks the server to build the authorize URL (credentials stay server-side).
    if (body?.action === "authorize_url") {
      const state = typeof body?.state === "string" && body.state.trim()
        ? body.state.trim()
        : crypto.randomUUID();
      const url = new URL(AUTHORIZE_URL);
      url.searchParams.set("client_id", clientId);
      url.searchParams.set("redirect_uri", redirectUri);
      url.searchParams.set("response_type", "code");
      url.searchParams.set("scope", DEFAULT_SCOPES);
      url.searchParams.set("state", state);
      return Response.json(
        {
          authorize_url: url.toString(),
          redirect_uri: redirectUri,
          audience,
          state,
        },
        { headers: CORS_HEADERS },
      );
    }

    const code = typeof body?.code === "string" ? body.code : null;
    const refreshToken =
      typeof body?.refresh_token === "string" ? body.refresh_token : null;

    if (!code && !refreshToken) {
      return Response.json(
        { error: "code, refresh_token, or action=authorize_url required" },
        { status: 400, headers: CORS_HEADERS },
      );
    }

    const params = new URLSearchParams({
      client_id: clientId,
      client_secret: clientSecret,
    });

    if (refreshToken) {
      params.set("grant_type", "refresh_token");
      params.set("refresh_token", refreshToken);
    } else {
      params.set("grant_type", "authorization_code");
      params.set("code", code!);
      params.set("redirect_uri", redirectUri);
      params.set("audience", audience);
    }

    const teslaRes = await fetch(TOKEN_URL, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: params,
    });

    const teslaJson = await teslaRes.json();
    if (!teslaRes.ok) {
      const message =
        typeof teslaJson?.error_description === "string"
          ? teslaJson.error_description
          : typeof teslaJson?.error === "string"
          ? teslaJson.error
          : "Tesla token exchange failed";
      return Response.json(
        { error: message },
        { status: teslaRes.status, headers: CORS_HEADERS },
      );
    }

    return Response.json(
      {
        access_token: teslaJson.access_token,
        refresh_token: teslaJson.refresh_token,
        expires_in: teslaJson.expires_in,
        token_type: teslaJson.token_type,
      },
      { headers: CORS_HEADERS },
    );
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : "Unknown error" },
      { status: 500, headers: CORS_HEADERS },
    );
  }
});
