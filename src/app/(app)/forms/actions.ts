"use server";

import { createClient } from "@/lib/supabase/server";
import { back, cleanError, field, optional } from "@/lib/actions";

const FORM_NAMES: Record<string, string> = {
  official_receipt: "Accountable Form No. 51",
  cash_ticket: "Cash Ticket",
  check: "Check",
};

// A booklet received from the City/Municipal Treasurer (ORs, cash tickets)
// or the bank (checks). Serials are issued from next_serial, one by one.
export async function addBooklet(formData: FormData) {
  const supabase = await createClient();
  const formType = field(formData, "form_type");
  const from = Number(field(formData, "serial_from"));
  const { error } = await supabase.from("accountable_form").insert({
    lgu_id: field(formData, "lgu_id"),
    barangay_id: field(formData, "barangay_id"),
    form_type: formType,
    form_name: FORM_NAMES[formType] ?? formType,
    series: optional(formData, "series"),
    serial_from: from,
    serial_to: Number(field(formData, "serial_to")),
    next_serial: from,
    received_on: optional(formData, "received_on"),
    issued_to_official_id: optional(formData, "issued_to_official_id"),
  });
  back("/forms", { error: error && cleanError(error.message), ok: "Booklet recorded. Its serials will be issued in order." });
}

export async function setBookletStatus(formData: FormData) {
  const supabase = await createClient();
  const { error } = await supabase
    .from("accountable_form")
    .update({ status: field(formData, "status") })
    .eq("id", field(formData, "id"));
  back("/forms", { error: error && cleanError(error.message), ok: "Booklet updated." });
}

// --- RAAF (Annex 18) ---

export async function prepareRaaf(formData: FormData) {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("prepare_raaf", {
    p_barangay: field(formData, "barangay_id"),
    p_year: Number(field(formData, "year")),
    p_month: Number(field(formData, "month")),
  });
  if (error) back("/forms/raaf", { error: cleanError(error.message) });
  back(`/forms/raaf/${(data as { id: string }).id}`, { ok: "Draft RAAF prepared. Check the balances against the booklets on hand, then certify." });
}

export async function certifyRaaf(formData: FormData) {
  const id = field(formData, "id");
  const supabase = await createClient();
  const { error } = await supabase.rpc("certify_raaf", { p_raaf: id });
  back(`/forms/raaf/${id}`, { error: error && cleanError(error.message), ok: "RAAF certified and numbered. Send it with the month's Transmittal Letter." });
}

export async function deleteRaaf(formData: FormData) {
  const id = field(formData, "id");
  const supabase = await createClient();
  const { error } = await supabase.from("raaf").delete().eq("id", id);
  if (error) back(`/forms/raaf/${id}`, { error: cleanError(error.message) });
  back("/forms/raaf", { ok: "Draft RAAF deleted." });
}
