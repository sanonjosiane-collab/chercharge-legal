// Bridges Tesla's HTTPS OAuth redirect to the Chercharge app custom URL scheme.
// Register this exact URL as the redirect_uri in the Tesla developer portal:
//   https://<PROJECT_REF>.supabase.co/functions/v1/tesla-oauth-callback
// Tesla redirects here with ?code=&state=; we 302 to chercharge://oauth/tesla?...

Deno.serve((req) => {
  const url = new URL(req.url);

  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers":
          "authorization, x-client-info, apikey, content-type",
      },
    });
  }

  const code = url.searchParams.get("code");
  const state = url.searchParams.get("state");
  const error = url.searchParams.get("error");
  const errorDescription = url.searchParams.get("error_description");

  const app = new URL("chercharge://oauth/tesla");
  if (error) {
    app.searchParams.set("error", error);
    if (errorDescription) {
      app.searchParams.set("error_description", errorDescription);
    }
  } else if (code) {
    app.searchParams.set("code", code);
    if (state) app.searchParams.set("state", state);
  } else {
    return new Response("Missing code or error from Tesla OAuth", {
      status: 400,
      headers: { "Content-Type": "text/plain" },
    });
  }

  return new Response(null, {
    status: 302,
    headers: {
      Location: app.toString(),
      "Cache-Control": "no-store",
    },
  });
});
