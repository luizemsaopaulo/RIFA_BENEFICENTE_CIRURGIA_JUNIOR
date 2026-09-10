import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
});

class GatewayError extends Error {
  status: number;
  code: string | null;
  details: string | null;
  hint: string | null;
  context: string | null;
  constructor(status: number, message: string, meta: { code?: string | null; details?: string | null; hint?: string | null; context?: string | null } = {}) {
    super(message);
    this.name = "GatewayError";
    this.status = status;
    this.code = meta.code || null;
    this.details = meta.details || null;
    this.hint = meta.hint || null;
    this.context = meta.context || null;
  }
}

function scalar(v: unknown): string | null {
  return typeof v === "string" && v.trim() ? v.trim() : null;
}

function errorMessage(error: unknown, fallback = "Erro interno."): string {
  if (error instanceof Error && error.message?.trim()) return error.message.trim();
  if (typeof error === "string" && error.trim()) return error.trim();
  if (error && typeof error === "object") {
    const e = error as Record<string, unknown>;
    const parts = [scalar(e.message), scalar(e.details), scalar(e.hint)].filter(Boolean) as string[];
    if (parts.length) return [...new Set(parts)].join(" • ");
    const code = scalar(e.code);
    if (code) return `Erro do banco (${code}).`;
  }
  return fallback;
}

function throwDbError(error: unknown, context: string): never {
  const e = (error && typeof error === "object" ? error : {}) as Record<string, unknown>;
  const code = scalar(e.code);
  const details = scalar(e.details);
  const hint = scalar(e.hint);
  const message = scalar(e.message) || errorMessage(error, `Falha no banco durante ${context}.`);
  const userConflict = code === "P0001" || code === "23505" || code === "23514" || code === "22023";
  const status = userConflict ? 409 : 500;
  console.error(`[junior-infinitepay-gateway] ${context}`, { code, message, details, hint, error });
  throw new GatewayError(status, message, { code, details, hint, context });
}

function badRequest(message: string): never { throw new GatewayError(400, message); }
function serviceUnavailable(message: string): never { throw new GatewayError(503, message); }

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const HANDLE = (Deno.env.get("JUNIOR_INFINITEPAY_HANDLE") || "antonio-junior-zzc").trim();
const PERSONAL_PIX_KEY = (Deno.env.get("JUNIOR_PERSONAL_PIX_KEY") || "").trim();
const PERSONAL_PIX_OWNER = (Deno.env.get("JUNIOR_PERSONAL_PIX_OWNER") || "").trim();

if (!SUPABASE_URL || !SERVICE_ROLE_KEY) throw new Error("Secrets padrão do Supabase indisponíveis na Edge Function.");
const db = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });

function assertHandle() {
  if (!HANDLE) serviceUnavailable("InfinitePay ainda não configurada para a rifa do Júnior.");
}

function assertPersonalPix() {
  if (!PERSONAL_PIX_KEY || !PERSONAL_PIX_OWNER) {
    serviceUnavailable("Pix pessoal ainda não configurado para a rifa do Júnior.");
  }
}

async function getOrder(orderNsu: string) {
  const { data, error } = await db
    .from("junior_reservations")
    .select("id,numbers,payment_status,expected_amount_cents,checkout_url,order_nsu")
    .eq("order_nsu", orderNsu)
    .single();
  if (error) throwDbError(error, "consulta do pedido");
  if (!data) badRequest("Pedido não encontrado.");
  return data;
}

async function verifyAndConfirm(payload: { order_nsu: string; transaction_nsu: string; slug: string; receipt_url?: string | null; }) {
  assertHandle();
  if (!payload.order_nsu || !payload.transaction_nsu || !payload.slug) badRequest("Dados do pagamento incompletos.");

  const order = await getOrder(payload.order_nsu);
  if (order.payment_status === "paid") return { success: true, ok: true, paid: true, already_paid: true };

  const checkResponse = await fetch("https://api.checkout.infinitepay.io/payment_check", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ handle: HANDLE, order_nsu: payload.order_nsu, transaction_nsu: payload.transaction_nsu, slug: payload.slug }),
  });
  if (!checkResponse.ok) throw new GatewayError(502, `Não foi possível validar o pagamento na InfinitePay (HTTP ${checkResponse.status}).`);
  const check = await checkResponse.json().catch(() => ({}));
  if (!check?.success || !check?.paid) return { success: true, ok: true, paid: false };

  const expected = Number(order.expected_amount_cents);
  const received = Number(check.amount);
  if (!Number.isFinite(received) || received !== expected) throw new GatewayError(409, `Valor divergente. Esperado ${expected}, recebido ${received}.`);

  const { data, error } = await db.rpc("junior_confirm_infinitepay_payment", {
    p_order_nsu: payload.order_nsu,
    p_transaction_nsu: payload.transaction_nsu,
    p_receipt_url: payload.receipt_url || null,
    p_capture_method: check.capture_method || null,
    p_amount_cents: received,
  });
  if (error) throwDbError(error, "confirmação do pagamento InfinitePay");
  return { success: true, ok: true, paid: true, data };
}

function normalizeBrazilPhone(value: unknown, requireMobile = false): string {
  let d = String(value ?? "").replace(/\D/g, "");
  if (!d) badRequest("Telefone não informado.");
  if (d.startsWith("00")) d = d.slice(2);
  if (d.startsWith("5555") && (d.length === 14 || d.length === 15)) d = d.slice(2);
  if (d.startsWith("55") && (d.length === 12 || d.length === 13)) d = d.slice(2);
  const validDdds = new Set(["11","12","13","14","15","16","17","18","19","21","22","24","27","28","31","32","33","34","35","37","38","41","42","43","44","45","46","47","48","49","51","53","54","55","61","62","63","64","65","66","67","68","69","71","73","74","75","77","79","81","82","83","84","85","86","87","88","89","91","92","93","94","95","96","97","98","99"]);
  if (d.length !== 10 && d.length !== 11) badRequest("Telefone inválido. Use DDD + número.");
  const ddd = d.slice(0, 2), subscriber = d.slice(2);
  if (!validDdds.has(ddd)) badRequest(`DDD ${ddd} inválido.`);
  if (d.length === 11 && subscriber[0] !== "9") badRequest("Celular inválido: depois do DDD, o número deve começar com 9.");
  if (d.length === 10 && requireMobile) badRequest("Para WhatsApp de celular, informe DDD + 9 dígitos.");
  if (d.length === 10 && !/^[2-9]/.test(subscriber)) badRequest("Telefone fixo inválido.");
  return d;
}

async function createPurchase(body: any) {
  assertHandle();
  const name = String(body.name || "").trim();
  const whatsapp = normalizeBrazilPhone(body.whatsapp, true);
  const numbers = Array.isArray(body.numbers) ? body.numbers.map(Number) : [];
  const redirectUrl = String(body.redirect_url || "");
  let redirect: URL;
  try { redirect = new URL(redirectUrl); } catch { badRequest("redirect_url inválida."); }
  if (!["http:", "https:"].includes(redirect!.protocol)) badRequest("redirect_url inválida.");

  const { data: started, error: startError } = await db.rpc("junior_start_infinitepay_payment", { p_name: name, p_whatsapp: whatsapp, p_numbers: numbers });
  if (startError) throwDbError(startError, "criação da reserva InfinitePay");
  const orderNsu = String(started?.order_nsu || ""), amount = Number(started?.amount_cents || 0);
  const selectedNumbers = Array.isArray(started?.numbers) ? started.numbers : numbers;
  if (!orderNsu) throw new GatewayError(500, "O banco não retornou o identificador da reserva InfinitePay.");
  const unitPrice = amount / selectedNumbers.length;
  if (!Number.isInteger(unitPrice) || unitPrice <= 0) {
    await db.rpc("junior_cancel_infinitepay_pending", { p_order_nsu: orderNsu });
    throw new GatewayError(500, "Valor unitário inválido no estado da rifa.");
  }

  try {
    const webhookUrl = `${SUPABASE_URL}/functions/v1/junior-infinitepay-gateway`;
    const response = await fetch("https://api.checkout.infinitepay.io/links", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        handle: HANDLE,
        redirect_url: redirect!.toString(),
        webhook_url: webhookUrl,
        order_nsu: orderNsu,
        customer: { name, phone_number: `+55${whatsapp}` },
        items: [{ quantity: selectedNumbers.length, price: unitPrice, description: `Rifa Beneficente Júnior - ${selectedNumbers.length} número(s)` }],
      }),
    });
    const result = await response.json().catch(() => ({}));
    if (!response.ok || !result?.url) throw new GatewayError(502, result?.message || `A InfinitePay não gerou o checkout (HTTP ${response.status}).`);

    const { error: updateError } = await db.from("junior_reservations").update({
      checkout_url: result.url,
      checkout_created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    }).eq("order_nsu", orderNsu);
    if (updateError) throwDbError(updateError, "gravação da URL do checkout InfinitePay");
    return { success: true, url: result.url, order_nsu: orderNsu, amount_cents: amount, numbers: selectedNumbers };
  } catch (error) {
    const { error: cancelError } = await db.rpc("junior_cancel_infinitepay_pending", { p_order_nsu: orderNsu });
    if (cancelError) console.error("[junior-infinitepay-gateway] falha ao liberar reserva após erro no checkout", cancelError);
    throw error;
  }
}

async function createPersonalPix(body: any) {
  assertPersonalPix();
  const name = String(body.name || "").trim(), whatsapp = normalizeBrazilPhone(body.whatsapp, true);
  const numbers = Array.isArray(body.numbers) ? body.numbers.map(Number) : [];
  const { data, error } = await db.rpc("junior_start_personal_pix_payment", { p_name: name, p_whatsapp: whatsapp, p_numbers: numbers });
  if (error) throwDbError(error, "criação da reserva Pix pessoal");
  return { success: true, order_nsu: data.order_nsu, amount_cents: data.amount_cents, numbers: data.numbers, expires_at: data.expires_at, pix_key: PERSONAL_PIX_KEY, pix_owner: PERSONAL_PIX_OWNER };
}

async function markPersonalPixContacted(orderNsu: string) {
  if (!orderNsu) badRequest("Pedido não informado.");
  const { data, error } = await db.rpc("junior_personal_pix_contacted", { p_order_nsu: orderNsu });
  if (error) throwDbError(error, "registro do contato do Pix pessoal");
  return { success: true, ...(data || {}) };
}

async function createCashPayment(body: any) {
  const name = String(body.name || "").trim(), whatsapp = normalizeBrazilPhone(body.whatsapp, true);
  const numbers = Array.isArray(body.numbers) ? body.numbers.map(Number) : [];
  const receivedBy = String(body.cash_received_by || "").trim();
  if (receivedBy.length < 2 || receivedBy.length > 80) badRequest("Informe corretamente quem recebeu o dinheiro.");
  const receivedPhone = normalizeBrazilPhone(body.cash_received_phone, false);
  const { data, error } = await db.rpc("junior_start_cash_payment", {
    p_name: name, p_whatsapp: whatsapp, p_numbers: numbers,
    p_cash_received_by: receivedBy, p_cash_received_phone: receivedPhone,
  });
  if (error) throwDbError(error, "criação da reserva em dinheiro");
  if (!data?.order_nsu) throw new GatewayError(500, "O banco não retornou os dados da reserva em dinheiro.");
  return { success: true, ...data };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ success: false, message: "Método não permitido." }, 405);
  let debug = false;
  try {
    const body = await req.json().catch(() => { throw new GatewayError(400, "Corpo JSON inválido."); });
    debug = body?.debug === true;
    const action = typeof body?.action === "string" ? body.action : "";
    console.info("[junior-infinitepay-gateway] request", { action: action || "webhook", numbers_count: Array.isArray(body?.numbers) ? body.numbers.length : undefined });
    if (action === "create") return json(await createPurchase(body));
    if (action === "create_personal_pix") return json(await createPersonalPix(body));
    if (action === "personal_pix_contacted") return json(await markPersonalPixContacted(String(body.order_nsu || "")));
    if (action === "create_cash_payment") return json(await createCashPayment(body));
    if (action === "confirm") return json(await verifyAndConfirm({ order_nsu: String(body.order_nsu || ""), transaction_nsu: String(body.transaction_nsu || ""), slug: String(body.slug || ""), receipt_url: body.receipt_url || null }));
    if (action) return json({ success: false, message: `Ação inválida: ${action}.` }, 400);

    const task = verifyAndConfirm({ order_nsu: String(body.order_nsu || ""), transaction_nsu: String(body.transaction_nsu || ""), slug: String(body.invoice_slug || body.slug || ""), receipt_url: body.receipt_url || null });
    const runtime = (globalThis as any).EdgeRuntime;
    if (runtime?.waitUntil) {
      runtime.waitUntil(task.catch((error: unknown) => console.error("Webhook InfinitePay Júnior:", error)));
      return json({ success: true, message: null });
    }
    await task;
    return json({ success: true, message: null });
  } catch (error) {
    const status = error instanceof GatewayError ? error.status : 500;
    const technicalMessage = errorMessage(error);
    const publicMessage = status >= 500
      ? "Não foi possível concluir a operação agora. Tente novamente. Se o problema continuar, o administrador pode consultar o diagnóstico da função."
      : technicalMessage;
    const payload: Record<string, unknown> = { success: false, message: debug ? technicalMessage : publicMessage };
    if (error instanceof GatewayError) {
      if (error.code) payload.code = error.code;
      if (debug) {
        if (error.details) payload.details = error.details;
        if (error.hint) payload.hint = error.hint;
        if (error.context) payload.context = error.context;
      }
    }
    console.error("[junior-infinitepay-gateway] request_error", { status, message: technicalMessage, error });
    return json(payload, status);
  }
});
