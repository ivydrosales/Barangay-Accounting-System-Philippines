"use server";

import { createClient } from "@/lib/supabase/server";
import { back, cleanError, field, optional } from "@/lib/actions";

const PAPER_FIELDS = [
  "paper_clt_beginning",
  "paper_clt_collection",
  "paper_clt_deposit",
  "paper_clt_ending",
  "paper_cib_beginning",
  "paper_cib_deposit",
  "paper_cib_check",
  "paper_cib_ending",
  "paper_or_count",
  "paper_check_count",
] as const;

// Saves the totals typed in from the paper Cashbook for one month.
// A blank box stays blank (not zero), so the report shows what is missing.
export async function savePaperFigures(formData: FormData) {
  const supabase = await createClient();
  const year = Number(field(formData, "year"));
  const month = Number(field(formData, "month"));
  const page = `/parallel-run?year=${year}&month=${month}`;
  const row: Record<string, string | number | null> = {
    lgu_id: field(formData, "lgu_id"),
    barangay_id: field(formData, "barangay_id"),
    period_year: year,
    period_month: month,
    notes: optional(formData, "notes"),
  };
  for (const f of PAPER_FIELDS) row[f] = optional(formData, f)?.replace(/,/g, "") ?? null;
  const { error } = await supabase.from("parallel_run_month").upsert(row, { onConflict: "barangay_id,period_year,period_month" });
  back(page, { error: error && cleanError(error.message), ok: "Paper figures saved. Check the differences below." });
}

export async function signOffParallelRun(formData: FormData) {
  const supabase = await createClient();
  const page = `/parallel-run?year=${field(formData, "year")}&month=${field(formData, "month")}`;
  const { error } = await supabase.rpc("sign_off_parallel_run", { p_id: field(formData, "id"), p_remarks: optional(formData, "remarks") });
  back(page, { error: error && cleanError(error.message), ok: "Month signed off. Its figures are now final." });
}
