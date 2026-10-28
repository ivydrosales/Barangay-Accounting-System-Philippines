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
