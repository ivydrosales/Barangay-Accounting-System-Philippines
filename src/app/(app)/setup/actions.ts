"use server";

import { createClient } from "@/lib/supabase/server";
import { back, cleanError, field, optional } from "@/lib/actions";

// Master data for running a barangay: its officials, its depository bank
// account, the LGU's barangays and suppliers, and who may sign in.

export async function addOfficial(formData: FormData) {
  const supabase = await createClient();
  const { error } = await supabase.from("official").insert({
    lgu_id: field(formData, "lgu_id"),
    barangay_id: field(formData, "barangay_id"),
    position: field(formData, "position"),
    full_name: field(formData, "full_name"),
    term_start: optional(formData, "term_start"),
    term_end: optional(formData, "term_end"),
    bond_amount: optional(formData, "bond_amount"),
    bond_expires_on: optional(formData, "bond_expires_on"),
  });
  back("/setup", { error: error && cleanError(error.message), ok: "Official added." });
}

export async function deactivateOfficial(formData: FormData) {
  const supabase = await createClient();
  const { error } = await supabase.from("official").update({ is_active: false }).eq("id", field(formData, "id"));
  back("/setup", { error: error && cleanError(error.message), ok: "Official marked as no longer in office. Past forms keep the name." });
}

export async function addBankAccount(formData: FormData) {
  const supabase = await createClient();
  const { error } = await supabase.from("bank_account").insert({
    lgu_id: field(formData, "lgu_id"),
    barangay_id: field(formData, "barangay_id"),
    bank_name: field(formData, "bank_name"),
    branch: optional(formData, "branch"),
    account_number: field(formData, "account_number"),
    account_name: field(formData, "account_name"),
    opened_on: optional(formData, "opened_on"),
  });
  back("/setup", { error: error && cleanError(error.message), ok: "Depository bank account recorded." });
}

export async function addBarangay(formData: FormData) {
  const supabase = await createClient();
  const { error } = await supabase.from("barangay").insert({ lgu_id: field(formData, "lgu_id"), name: field(formData, "name") });
  back("/setup", { error: error && cleanError(error.message), ok: "Barangay added with its five standard funds." });
}

export async function addSupplier(formData: FormData) {
  const supabase = await createClient();
  const { error } = await supabase.from("supplier").insert({
    lgu_id: field(formData, "lgu_id"),
    name: field(formData, "name"),
    tin: optional(formData, "tin"),
    address: optional(formData, "address"),
  });
  back("/setup", { error: error && cleanError(error.message), ok: "Supplier added." });
}

export async function grantAccess(formData: FormData) {
  const supabase = await createClient();
  const { error } = await supabase.rpc("grant_access", {
    p_lgu: field(formData, "lgu_id"),
    p_email: field(formData, "email"),
    p_role: field(formData, "role"),
    p_barangay: optional(formData, "barangay_id"),
  });
  back("/setup/people", { error: error && cleanError(error.message), ok: "Access given. They can sign in now." });
}

export async function revokeAccess(formData: FormData) {
  const supabase = await createClient();
  const { error } = await supabase.rpc("revoke_access", { p_membership: field(formData, "id") });
  back("/setup/people", { error: error && cleanError(error.message), ok: "Access removed." });
}
