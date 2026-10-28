"use server";

import { createClient } from "@/lib/supabase/server";
import { back, cleanError, field, optional } from "@/lib/actions";

// Every action calls a database function. The database holds the rules
// (who signs which box, the sequence of numbers, closed periods) and returns
// a plain-language message when something is not allowed.

type LineKind = "charge" | "deduction";
type LineInput = { kind: LineKind; account_code: string; amount: string; particulars: string | null };

const ACCOUNT_CODE = /^[1-5]-\d{2}-\d{2}-\d{3}$/;

// The Prepare DV form has a fixed number of rows per kind; empty rows are skipped.
function collectLines(formData: FormData, kind: LineKind): LineInput[] {
  const codes = formData.getAll(`${kind}_account`).map(String);
  const amounts = formData.getAll(`${kind}_amount`).map(String);
  const notes = formData.getAll(`${kind}_particulars`).map(String);
  return codes.flatMap((raw, i) => {
    const code = raw.trim();
    const amount = (amounts[i] ?? "").trim();
    if (!code && !amount) return [];
    return [{ kind, account_code: code, amount, particulars: (notes[i] ?? "").trim() || null }];
  });
}

export async function createDv(formData: FormData) {
  const supabase = await createClient();
  const lines = [...collectLines(formData, "charge"), ...collectLines(formData, "deduction")];

  // People may type the account title instead of picking the code.
  for (const line of lines) {
    if (!line.account_code || ACCOUNT_CODE.test(line.account_code)) continue;
    const { data } = await supabase.from("account").select("code").ilike("title", line.account_code).limit(2);
    if (data?.length === 1) line.account_code = data[0].code;
    else back("/disbursements", { error: `"${line.account_code}" is not an account code or an exact account title.` });
  }

  const { data, error } = await supabase.rpc("create_dv", {
    p_barangay: field(formData, "barangay_id"),
    p_fund: field(formData, "fund_id"),
    p_date: field(formData, "dv_date"),
    p_payee: field(formData, "payee"),
    p_particulars: field(formData, "particulars"),
    p_lines: lines,
    p_payee_tin: optional(formData, "payee_tin"),
    p_payee_address: optional(formData, "payee_address"),
    p_supplier: optional(formData, "supplier_id"),
    p_employee: optional(formData, "employee_id"),
  });
  if (error) back("/disbursements", { error: cleanError(error.message) });
  const dv = data as { id: string; dv_no: string };
  back(`/disbursements/${dv.id}`, { ok: `DV No. ${dv.dv_no} prepared. Attach the supporting documents and pass it to the CCA for Box A.` });
}

export async function cancelDv(formData: FormData) {
  const id = field(formData, "id");
  const supabase = await createClient();
  const { error } = await supabase.rpc("cancel_dv", { p_dv: id, p_reason: field(formData, "reason") });
  back(`/disbursements/${id}`, { error: error && cleanError(error.message), ok: "DV cancelled. It keeps its number and stays on file." });
}

export async function certifyBoxA(formData: FormData) {
  const id = field(formData, "id");
  const supabase = await createClient();
  const { error } = await supabase.rpc("certify_dv_box_a", { p_dv: id });
  back(`/disbursements/${id}`, { error: error && cleanError(error.message), ok: "Box A signed. The Treasurer certifies Box B next." });
}

export async function certifyBoxB(formData: FormData) {
  const id = field(formData, "id");
  const supabase = await createClient();
  const { error } = await supabase.rpc("certify_dv_box_b", { p_dv: id });
  back(`/disbursements/${id}`, { error: error && cleanError(error.message), ok: "Box B signed. The Punong Barangay approves Box C next." });
}

export async function approveDv(formData: FormData) {
  const id = field(formData, "id");
  const supabase = await createClient();
  const { error } = await supabase.rpc("approve_dv", { p_dv: id });
  back(`/disbursements/${id}`, { error: error && cleanError(error.message), ok: "Box C signed. The Treasurer may now draw the check." });
}

export async function issueCheck(formData: FormData) {
  const id = field(formData, "id");
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("issue_check", {
    p_dv: id,
    p_check_booklet: field(formData, "booklet_id"),
    p_check_date: field(formData, "check_date"),
  });
  const check = data as { check_no: number; pbc_no: string } | null;
  back(`/disbursements/${id}`, {
    error: error && cleanError(error.message),
    ok: `Check No. ${check?.check_no} drawn with PB Certification No. ${check?.pbc_no}. It is now in the Cashbook under Cash in Bank.`,
  });
}

export async function releaseCheck(formData: FormData) {
  const id = field(formData, "id");
  const supabase = await createClient();
  const { error } = await supabase.rpc("release_check", {
    p_dv: id,
    p_received_by: field(formData, "received_by"),
    p_received_on: field(formData, "received_on"),
    p_payee_or_no: optional(formData, "payee_or_no"),
  });
  back(`/disbursements/${id}`, { error: error && cleanError(error.message), ok: "Box D recorded. The DV is paid and will go on this month's Transmittal Letter." });
}

export async function postDv(formData: FormData) {
  const id = field(formData, "id");
  const supabase = await createClient();
  const { error } = await supabase.rpc("post_dv", { p_dv: id });
  back(`/disbursements/${id}`, { error: error && cleanError(error.message), ok: "DV posted to the Journal of Cash Transactions." });
}

// --- Transmittal Letter (Annex 16) ---

export async function prepareTransmittal(formData: FormData) {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("prepare_transmittal", {
    p_barangay: field(formData, "barangay_id"),
    p_year: Number(field(formData, "year")),
    p_month: Number(field(formData, "month")),
    p_date: optional(formData, "tl_date"),
  });
  if (error) back("/disbursements/transmittal", { error: cleanError(error.message) });
  back(`/disbursements/transmittal/${(data as { id: string }).id}`, { ok: "Draft Transmittal Letter prepared. Add any other reports, then submit." });
}

export async function submitTransmittal(formData: FormData) {
  const id = field(formData, "id");
  const supabase = await createClient();
  const { error } = await supabase.rpc("submit_transmittal", { p_tl: id });
  back(`/disbursements/transmittal/${id}`, { error: error && cleanError(error.message), ok: "Transmittal Letter numbered and submitted to the Accountant." });
}

export async function receiveTransmittal(formData: FormData) {
  const id = field(formData, "id");
  const supabase = await createClient();
  const { error } = await supabase.rpc("receive_transmittal", { p_tl: id, p_received_by: field(formData, "received_by") });
  back(`/disbursements/transmittal/${id}`, { error: error && cleanError(error.message), ok: "Receipt acknowledged." });
}

export async function deleteTransmittal(formData: FormData) {
  const id = field(formData, "id");
  const supabase = await createClient();
  const { error } = await supabase.from("transmittal_letter").delete().eq("id", id);
  if (error) back(`/disbursements/transmittal/${id}`, { error: cleanError(error.message) });
  back("/disbursements/transmittal", { ok: "Draft Transmittal Letter deleted. Its DVs and RCDs are untransmitted again." });
}

export async function addOtherReport(formData: FormData) {
  const id = field(formData, "transmittal_id");
  const supabase = await createClient();
  const { error } = await supabase.from("tl_other_report").insert({
    transmittal_id: id,
    report_date: field(formData, "report_date"),
    report_type: field(formData, "report_type"),
  });
  back(`/disbursements/transmittal/${id}`, { error: error && cleanError(error.message), ok: "Report added to section C." });
}

export async function deleteOtherReport(formData: FormData) {
  const id = field(formData, "transmittal_id");
  const supabase = await createClient();
  const { error } = await supabase.from("tl_other_report").delete().eq("id", field(formData, "id"));
  back(`/disbursements/transmittal/${id}`, { error: error && cleanError(error.message), ok: "Report removed." });
}
