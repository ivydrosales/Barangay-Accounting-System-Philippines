import { redirect } from "next/navigation";

// Server actions end by sending the person back to a page with a message.
// redirect() throws, so it is called outside any try/catch.
export function back(path: string, result: { ok?: string; error?: string | null }): never {
  const url = new URL(path, "http://local");
  if (result.error) url.searchParams.set("error", result.error);
  else if (result.ok) url.searchParams.set("ok", result.ok);
  redirect(url.pathname + url.search);
}

// Postgres raises plain-language messages; strip the noise Supabase adds.
export function cleanError(message: string | undefined | null): string {
  if (!message) return "Something went wrong.";
  return message.replace(/^.*?ERROR:\s*/i, "").replace(/\s*\(SQLSTATE.*$/, "");
}

export function field(formData: FormData, name: string): string {
  return String(formData.get(name) ?? "").trim();
}

export function optional(formData: FormData, name: string): string | null {
  const v = field(formData, name);
  return v === "" ? null : v;
}
