import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const BUCKET = "junior-public-media";
const MAX_BYTES = 8 * 1024 * 1024;
const ALLOWED_ORIGINS = new Set(["https://luizemsaopaulo.github.io"]);

const db = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

class HttpError extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

function corsHeaders(req: Request) {
  const origin = req.headers.get("origin") || "";
  const local = /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/i.test(origin);
  const allow = ALLOWED_ORIGINS.has(origin) || local ? origin : "https://luizemsaopaulo.github.io";
  return {
    "Access-Control-Allow-Origin": allow,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

function json(req: Request, body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(req), "Content-Type": "application/json; charset=utf-8" },
  });
}

async function validateSession(token: string) {
  if (!token) throw new HttpError(401, "Sessão administrativa ausente.");
  const { data, error } = await db.rpc("junior_admin_media_session_validate", {
    p_session_token: token,
  });
  if (error) {
    console.error("session_validate", error);
    throw new HttpError(500, "Validador da sessão não está instalado. Execute o SQL da foto do Admin.");
  }
  if (data !== true) throw new HttpError(401, "Sessão administrativa inválida ou expirada.");
}

async function currentPath(): Promise<string | null> {
  const { data, error } = await db
    .from("junior_raffle_public_state")
    .select("beneficiary_photo_path")
    .eq("id", 1)
    .single();
  if (error) throw new HttpError(500, "Campo da foto não está disponível. Execute o SQL de atualização.");
  return data?.beneficiary_photo_path || null;
}

function publicUrl(path: string | null) {
  if (!path) return null;
  const encoded = path.split("/").map(encodeURIComponent).join("/");
  return `${SUPABASE_URL}/storage/v1/object/public/${BUCKET}/${encoded}`;
}

function detectImage(bytes: Uint8Array): { mime: string; ext: string } | null {
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
    return { mime: "image/jpeg", ext: "jpg" };
  }
  if (
    bytes.length >= 8 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e &&
    bytes[3] === 0x47 && bytes[4] === 0x0d && bytes[5] === 0x0a && bytes[6] === 0x1a && bytes[7] === 0x0a
  ) {
    return { mime: "image/png", ext: "png" };
  }
  if (
    bytes.length >= 12 && String.fromCharCode(...bytes.slice(0, 4)) === "RIFF" &&
    String.fromCharCode(...bytes.slice(8, 12)) === "WEBP"
  ) {
    return { mime: "image/webp", ext: "webp" };
  }
  return null;
}

async function setActivePath(path: string | null) {
  const { error } = await db
    .from("junior_raffle_public_state")
    .update({ beneficiary_photo_path: path, updated_at: new Date().toISOString() })
    .eq("id", 1);
  if (error) throw new HttpError(500, "Não foi possível salvar a foto ativa no banco.");
}

async function deleteStoragePath(path: string | null) {
  if (!path || !path.startsWith("beneficiary/")) return null;
  const { error } = await db.storage.from(BUCKET).remove([path]);
  return error?.message || null;
}

async function parseRequest(req: Request) {
  const type = req.headers.get("content-type") || "";
  if (type.includes("multipart/form-data")) {
    const form = await req.formData();
    return {
      action: String(form.get("action") || ""),
      token: String(form.get("session_token") || ""),
      file: form.get("file"),
    };
  }
  const body = await req.json().catch(() => ({}));
  return {
    action: String(body?.action || ""),
    token: String(body?.session_token || ""),
    file: null,
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders(req) });
  if (req.method !== "POST") return json(req, { success: false, message: "Método não permitido." }, 405);

  try {
    const { action, token, file } = await parseRequest(req);
    await validateSession(token);

    if (action === "status") {
      const path = await currentPath();
      return json(req, { success: true, path, url: publicUrl(path) });
    }

    if (action === "upload") {
      if (!(file instanceof File)) throw new HttpError(400, "Escolha uma foto para enviar.");
      if (file.size <= 0) throw new HttpError(400, "O arquivo da foto está vazio.");
      if (file.size > MAX_BYTES) throw new HttpError(413, "A foto excede o limite de 8 MB.");

      const raw = new Uint8Array(await file.arrayBuffer());
      const detected = detectImage(raw);
      if (!detected) throw new HttpError(415, "Formato inválido. Use JPG, JPEG, PNG ou WEBP.");

      const oldPath = await currentPath();
      const stamp = new Date().toISOString().replace(/[-:.TZ]/g, "").slice(0, 14);
      const unique = crypto.randomUUID().replaceAll("-", "").slice(0, 12);
      const newPath = `beneficiary/junior-${stamp}-${unique}.${detected.ext}`;

      const { error: uploadError } = await db.storage.from(BUCKET).upload(newPath, raw, {
        contentType: detected.mime,
        cacheControl: "31536000",
        upsert: false,
      });
      if (uploadError) {
        console.error("upload", uploadError);
        throw new HttpError(500, "Não foi possível enviar a foto para o Storage.");
      }

      try {
        await setActivePath(newPath);
      } catch (e) {
        await deleteStoragePath(newPath);
        throw e;
      }

      const cleanupWarning = oldPath && oldPath !== newPath ? await deleteStoragePath(oldPath) : null;
      return json(req, {
        success: true,
        path: newPath,
        url: publicUrl(newPath),
        cleanup_warning: cleanupWarning,
      });
    }

    if (action === "remove") {
      const oldPath = await currentPath();
      await setActivePath(null);
      const cleanupWarning = await deleteStoragePath(oldPath);
      return json(req, {
        success: true,
        path: null,
        url: null,
        cleanup_warning: cleanupWarning,
      });
    }

    throw new HttpError(400, "Ação inválida.");
  } catch (error) {
    const status = error instanceof HttpError ? error.status : 500;
    const message = error instanceof Error ? error.message : "Erro interno.";
    console.error("junior-admin-media", error);
    return json(req, { success: false, message }, status);
  }
});
