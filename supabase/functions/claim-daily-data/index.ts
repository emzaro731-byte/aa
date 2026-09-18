import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Content-Type": "application/json",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseKey = Deno.env.get("SUPABASE_ANON_KEY");
    const vtuToken = Deno.env.get("VTU_API_TOKEN");

    if (!supabaseUrl || !supabaseKey) {
      return new Response(JSON.stringify({ ok: false, error: "Supabase configuration is missing." }), { status: 500, headers: cors });
    }
    if (!vtuToken) {
      return new Response(JSON.stringify({ ok: false, error: "VTU_API_TOKEN is not configured yet." }), { status: 503, headers: cors });
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return new Response(JSON.stringify({ ok: false, error: "Authorization required." }), { status: 401, headers: cors });

    const supabase = createClient(supabaseUrl, supabaseKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: { user }, error: userError } = await supabase.auth.getUser();
    if (userError || !user) return new Response(JSON.stringify({ ok: false, error: "You must be signed in." }), { status: 401, headers: cors });

    const body = await req.json();
    const phone = String(body.phone ?? "").trim();
    const network = String(body.network ?? "").trim().toLowerCase();

    if (!/^\+?234\d{10}$|^0\d{10}$/.test(phone)) {
      return new Response(JSON.stringify({ ok: false, error: "Enter a valid Nigerian phone number." }), { status: 400, headers: cors });
    }
    if (!["mtn", "airtel", "glo", "9mobile"].includes(network)) {
      return new Response(JSON.stringify({ ok: false, error: "Unsupported network." }), { status: 400, headers: cors });
    }

    const today = new Date().toISOString().slice(0, 10);
    const { data: existing } = await supabase
      .from("data_claims").select("id,status").eq("user_id", user.id)
      .eq("claim_date", today).in("status", ["pending", "success"]).maybeSingle();

    if (existing) {
      return new Response(JSON.stringify({ ok: false, error: "Today's data reward has already been claimed.", claim_id: existing.id }), { status: 409, headers: cors });
    }

    const { data: plan, error: planError } = await supabase
      .from("data_plans").select("variation_id,network,gb")
      .eq("network", network).eq("active", true).gte("gb", 1)
      .order("gb", { ascending: true }).limit(1).maybeSingle();

    if (planError || !plan) {
      return new Response(JSON.stringify({ ok: false, error: "No active 1 GB plan is configured for this network yet." }), { status: 404, headers: cors });
    }

    const requestId = "aa_" + crypto.randomUUID().replaceAll("-", "");
    const { data: claim, error: claimError } = await supabase.from("data_claims")
      .insert({ user_id: user.id, phone, network, variation_id: String(plan.variation_id), status: "pending", claim_date: today })
      .select("id").single();

    if (claimError || !claim) {
      return new Response(JSON.stringify({ ok: false, error: "Could not reserve today's reward. Try again." }), { status: 409, headers: cors });
    }

    const providerResponse = await fetch("https://vtu.ng/wp-json/api/v2/data", {
      method: "POST",
      headers: { "Authorization": "Bearer " + vtuToken, "Content-Type": "application/json" },
      body: JSON.stringify({ request_id: requestId, phone, service_id: network, variation_id: String(plan.variation_id) }),
    });

    const raw = await providerResponse.text();
    let providerJson: unknown;
    try { providerJson = JSON.parse(raw); } catch { providerJson = { raw }; }

    const providerReference = typeof providerJson === "object" && providerJson !== null
      ? String((providerJson as Record<string, unknown>).reference ?? (providerJson as Record<string, unknown>).transaction_id ?? requestId)
      : requestId;

    const status = providerResponse.ok ? "success" : "failed";
    await supabase.from("data_claims").update({
      status, provider_reference: providerReference, provider_response: providerJson,
      updated_at: new Date().toISOString(),
    }).eq("id", claim.id);

    if (!providerResponse.ok) {
      return new Response(JSON.stringify({ ok: false, error: "The data provider rejected the purchase.", claim_id: claim.id, provider_status: providerResponse.status }), { status: 502, headers: cors });
    }

    return new Response(JSON.stringify({
      ok: true, message: "1 GB data purchase submitted successfully.",
      claim_id: claim.id, network, phone, provider_reference: providerReference,
    }), { status: 200, headers: cors });
  } catch (error) {
    return new Response(JSON.stringify({ ok: false, error: error instanceof Error ? error.message : "Unexpected server error." }), { status: 500, headers: cors });
  }
});
