"use server";

import { createClient } from "@/lib/supabase/server";
import { back, cleanError, field, optional } from "@/lib/actions";

// Every action calls a database function; the database holds the rules and
// returns a plain-language message when something is not allowed.

export async function issueOr(formData: FormData) {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("issue_official_receipt", {
    p_form: field(formData, "form_id"),
    p_date: field(formData, "or_date"),
    p_payor: field(formData, "payor"),
    p_collection_type: field(formData, "collection_type_id"),
    p_fund: field(formData, "fund_id"),
    p_amount: field(formData, "amount"),
    p_mode: field(formData, "payment_mode") || "cash",
    p_check_bank: optional(formData, "check_bank"),
    p_check_no: optional(formData, "check_no"),
    p_check_date: optional(formData, "check_date"),
    p_particulars: optional(formData, "particulars"),
  });
  const serial = (data as { serial_no?: number } | null)?.serial_no;
  back("/collections", { error: error && cleanError(error.message), ok: `OR No. ${serial} issued.` });
}

export async function cancelOr(formData: FormData) {
  const supabase = await createClient();
  const { error } = await supabase.rpc("cancel_official_receipt", {
    p_or: field(formData, "id"),
    p_reason: field(formData, "reason"),
  });
  back("/collections", { error: error && cleanError(error.message), ok: "OR cancelled. It stays on the report." });
}

export async function prepareRcr(formData: FormData) {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("prepare_rcr", {
    p_barangay: field(formData, "barangay_id"),
    p_date: field(formData, "rcr_date"),
    p_collector: field(formData, "collector_id"),
  });
  if (error) back("/collections/rcr", { error: cleanError(error.message) });
  back(`/collections/rcr/${(data as { id: string }).id}`, { ok: "Draft RCR prepared. Check it, then certify." });
}

export async function certifyRcr(formData: FormData) {
  const id = field(formData, "id");
  const supabase = await createClient();
  const { error } = await supabase.rpc("certify_rcr", { p_rcr: id });
  back(`/collections/rcr/${id}`, { error: error && cleanError(error.message), ok: "RCR certified and numbered." });
}

export async function acknowledgeRcr(formData: FormData) {
  const id = field(formData, "id");
  const supabase = await createClient();
  const { error } = await supabase.rpc("acknowledge_rcr", { p_rcr: id });
  back(`/collections/rcr/${id}`, { error: error && cleanError(error.message), ok: "Receipt of the collections acknowledged." });
}

export async function deleteRcr(formData: FormData) {
  const id = field(formData, "id");
  const supabase = await createClient();
  const { error } = await supabase.from("rcr").delete().eq("id", id);
  if (error) back(`/collections/rcr/${id}`, { error: cleanError(error.message) });
  back("/collections/rcr", { ok: "Draft RCR deleted. Its ORs are unreported again." });
}

export async function addDeposit(formData: FormData) {
  const supabase = await createClient();
  const barangayId = field(formData, "barangay_id");
  // a deposit recorded while a draft RCD is open goes straight onto it
  const { data: draft } = await supabase
    .from("rcd")
    .select("id, rcd_date")
    .eq("barangay_id", barangayId)
    .eq("status", "draft")
    .maybeSingle();
  const depositDate = field(formData, "deposit_date");
  const { error } = await supabase.from("deposit").insert({
    lgu_id: field(formData, "lgu_id"),
    barangay_id: barangayId,
    bank_account_id: field(formData, "bank_account_id"),
    fund_id: field(formData, "fund_id"),
    deposit_date: depositDate,
    reference: field(formData, "reference"),
    amount: field(formData, "amount"),
    rcd_id: draft && depositDate <= draft.rcd_date ? draft.id : null,
  });
  back("/collections/rcd", { error: error && cleanError(error.message), ok: "Deposit recorded." });
}

export async function deleteDeposit(formData: FormData) {
  const supabase = await createClient();
  const { error } = await supabase.from("deposit").delete().eq("id", field(formData, "id"));
  back(field(formData, "return_to") || "/collections/rcd", { error: error && cleanError(error.message), ok: "Deposit removed." });
}

export async function prepareRcd(formData: FormData) {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("prepare_rcd", {
    p_barangay: field(formData, "barangay_id"),
    p_date: field(formData, "rcd_date"),
  });
  if (error) back("/collections/rcd", { error: cleanError(error.message) });
  back(`/collections/rcd/${(data as { id: string }).id}`, { ok: "Draft RCD prepared. Check it, then certify." });
}

export async function certifyRcd(formData: FormData) {
  const id = field(formData, "id");
  const supabase = await createClient();
  const { error } = await supabase.rpc("certify_rcd", { p_rcd: id });
  back(`/collections/rcd/${id}`, { error: error && cleanError(error.message), ok: "RCD certified and numbered. It now appears in the Cashbook." });
}

export async function postRcd(formData: FormData) {
  const id = field(formData, "id");
  const supabase = await createClient();
  const { error } = await supabase.rpc("post_rcd", { p_rcd: id });
  back(`/collections/rcd/${id}`, { error: error && cleanError(error.message), ok: "RCD posted to the Journal of Cash Transactions." });
}

export async function deleteRcd(formData: FormData) {
  const id = field(formData, "id");
  const supabase = await createClient();
  const { error } = await supabase.from("rcd").delete().eq("id", id);
  if (error) back(`/collections/rcd/${id}`, { error: cleanError(error.message) });
  back("/collections/rcd", { ok: "Draft RCD deleted. Its ORs, RCRs and deposits are unreported again." });
}
