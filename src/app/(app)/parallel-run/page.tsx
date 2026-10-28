import Link from "next/link";
import { Flash } from "@/components/Flash";
import { PrintButton } from "@/components/PrintButton";
import { requireBarangay } from "@/lib/context";
import { MONTHS, formatAmount, formatDate, todayManila } from "@/lib/format";
import { savePaperFigures, signOffParallelRun } from "./actions";

type Row = { line_no: number; section: string; figure: string; paper: string | null; system: string | null; difference: string | null };
type Saved = {
  id: string;
  notes: string | null;
  signed_off_at: string | null;
  signoff_remarks: string | null;
  [key: string]: string | number | null;
};

// The paper box that feeds each line of the comparison.
const INPUTS: Record<number, string> = {
  1: "paper_clt_beginning",
  2: "paper_clt_collection",
  3: "paper_clt_deposit",
  4: "paper_clt_ending",
  5: "paper_cib_beginning",
  6: "paper_cib_deposit",
  7: "paper_cib_check",
  8: "paper_cib_ending",
  9: "paper_or_count",
  10: "paper_check_count",
};
const COUNTS = new Set([9, 10]);

function show(lineNo: number, value: string | null) {
  if (value === null) return "";
  if (COUNTS.has(lineNo)) return String(Number(value));
  return Number(value) === 0 ? "0.00" : formatAmount(value);
}

export default async function ParallelRunPage({
  searchParams,
}: {
  searchParams: Promise<{ year?: string; month?: string; ok?: string; error?: string }>;
}) {
  const sp = await searchParams;
  const today = todayManila();
  // Default to last month: the comparison is done after the month closes.
  const prev = new Date(Date.UTC(Number(today.slice(0, 4)), Number(today.slice(5, 7)) - 2, 1));
  const year = Number(sp.year ?? prev.getUTCFullYear());
  const month = Number(sp.month ?? prev.getUTCMonth() + 1);
  const { supabase, barangay, canWrite, isLguStaff } = await requireBarangay();

  const [{ data: rowData }, { data: savedRow }] = await Promise.all([
    supabase.rpc("parallel_run_comparison", { p_barangay: barangay.id, p_year: year, p_month: month }),
    supabase
      .from("parallel_run_month")
      .select("*")
      .eq("barangay_id", barangay.id)
      .eq("period_year", year)
      .eq("period_month", month)
      .maybeSingle(),
  ]);
  const rows = (rowData ?? []) as Row[];
  const saved = (savedRow ?? null) as Saved | null;
  const signedOff = Boolean(saved?.signed_off_at);
  const blanks = rows.filter((r) => r.paper === null).length;
  const differing = rows.filter((r) => r.difference !== null && Number(r.difference) !== 0).length;
  const monthName = `${MONTHS[month - 1]} ${year}`;
  const years = [year - 1, year, year + 1];

  return (
    <>
      <header className="row no-print">
        <div>
          <h1>Parallel run</h1>
          <p className="muted">
            {barangay.name} · the Phase 1 test: one month kept in the system and on paper side by side, until the totals match
          </p>
        </div>
        <div className="actions">
          <form method="get" className="inline-form">
            <select name="month" defaultValue={month} aria-label="Month">
              {MONTHS.map((m, i) => (
                <option key={m} value={i + 1}>
                  {m}
                </option>
              ))}
            </select>
            <select name="year" defaultValue={year} aria-label="Year">
              {years.map((y) => (
                <option key={y} value={y}>
                  {y}
                </option>
              ))}
            </select>
            <button type="submit" className="secondary small">
              Show
            </button>
          </form>
          <PrintButton />
        </div>
      </header>
      <Flash ok={sp.ok} error={sp.error} />

      <article className="annex">
        <h2 className="annex-title">
          PARALLEL RUN: SYSTEM TOTALS AGAINST THE PAPER CASHBOOK
          <br />
          <span style={{ fontWeight: 400, fontSize: 12 }}>
            Barangay {barangay.name} · For the Month of {monthName}
          </span>
        </h2>
        <table className="annex-table">
          <thead>
            <tr>
              <th>Section</th>
              <th>Figure</th>
              <th className="num">Paper</th>
              <th className="num">System</th>
              <th className="num">Difference (system less paper)</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => {
              const off = r.difference !== null && Number(r.difference) !== 0;
              return (
                <tr key={r.line_no} style={off ? { fontWeight: 700 } : undefined}>
                  <td>{r.section}</td>
                  <td>{r.figure}</td>
                  <td className="num">{r.paper === null ? <span className="muted">not entered</span> : show(r.line_no, r.paper)}</td>
                  <td className="num">{show(r.line_no, r.system)}</td>
                  <td className="num">{r.difference === null ? "" : off ? show(r.line_no, r.difference) : "none"}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
        <p>
          {blanks > 0
            ? `${blanks} paper figure(s) not entered yet.`
            : differing === 0
              ? "Every figure agrees."
              : `${differing} figure(s) differ. Each needs an explanation before the Accountant signs off.`}{" "}
          Cash advances and petty cash are not compared yet; they come with Phase 3. Until opening balances are loaded (Phase 2) the
          system starts from zero, so a beginning-balance difference carries into the ending balance.
        </p>
        {saved?.notes && <p>Treasurer&apos;s notes: {saved.notes}</p>}
        <div className="annex-box">
          <strong>Accountant&apos;s sign-off</strong>
          <p>{signedOff ? saved?.signoff_remarks ?? "Totals agree." : "Not signed off."}</p>
          <div className="sig-row">
            <div className="sig">
              <div className="sig-line">&nbsp;</div>
              <div className="sig-label">City/Municipal Accountant</div>
            </div>
            <div className="sig">
              <div className="sig-line">{signedOff ? formatDate(saved?.signed_off_at?.slice(0, 10)) : ""}</div>
              <div className="sig-label">Date</div>
            </div>
          </div>
        </div>
      </article>

      {canWrite && !signedOff && (
        <section className="card">
          <h2>Type in the paper totals for {monthName}</h2>
          <p className="muted">
            Copy each figure from the paper Cashbook (Annex 8) totals line and from the OR and check booklets. Leave a box blank if
            you do not have the figure yet.
          </p>
          <form action={savePaperFigures} className="grid">
            <input type="hidden" name="lgu_id" value={barangay.lgu_id} />
            <input type="hidden" name="barangay_id" value={barangay.id} />
            <input type="hidden" name="year" value={year} />
            <input type="hidden" name="month" value={month} />
            {rows.map((r) => (
              <label key={r.line_no}>
                {r.section}: {r.figure}
                <input
                  name={INPUTS[r.line_no]}
                  type="number"
                  step={COUNTS.has(r.line_no) ? 1 : 0.01}
                  min={COUNTS.has(r.line_no) ? 0 : undefined}
                  defaultValue={r.paper === null ? "" : COUNTS.has(r.line_no) ? Number(r.paper) : r.paper}
                />
              </label>
            ))}
            <label className="span2">
              Notes (what explains any difference)
              <textarea name="notes" rows={3} defaultValue={saved?.notes ?? ""} />
            </label>
            <div className="span2">
              <button type="submit">Save paper figures</button>
            </div>
          </form>
        </section>
      )}

      {isLguStaff && saved && !signedOff && (
        <section className="card">
          <h2>Sign off {monthName} (Accountant)</h2>
          <p className="muted">
            Sign off when every figure agrees, or every difference is explained. Remarks are required when a figure differs. The
            figures are final after sign-off.
          </p>
          <form action={signOffParallelRun} className="grid">
            <input type="hidden" name="id" value={saved.id} />
            <input type="hidden" name="year" value={year} />
            <input type="hidden" name="month" value={month} />
            <label className="span2">
              Remarks
              <textarea name="remarks" rows={2} />
            </label>
            <div className="span2">
              <button type="submit">Sign off the month</button>
            </div>
          </form>
        </section>
      )}

      <article className="annex">
        <h2 className="annex-title">PARALLEL-RUN CHECKLIST</h2>
        <p>
          For one full month the pilot barangay keeps its paper forms and books exactly as before, and enters the same
          transactions in the system on the same day. The numbers on paper (OR, check, DV) must be the same numbers in the
          system. The month passes when the Accountant signs off the comparison above.
        </p>

        <h3 className="annex-section">Before the month starts (Treasurer, with the LGU administrator)</h3>
        <ol>
          <li>Check that the officials (Punong Barangay, Treasurer, CCA, collectors) and their logins are set up.</li>
          <li>
            Record every OR booklet, cash ticket booklet and checkbook on hand under <Link href="/forms">Accountable forms</Link>,
            with the next unused serial number as it is on paper.
          </li>
          <li>Check that the depository bank account is recorded.</li>
        </ol>

        <h3 className="annex-section">Every day (Treasurer and collectors)</h3>
        <ol>
          <li>
            Issue each <Link href="/collections">Official Receipt</Link> in the system as it is written on paper: same number,
            payor, nature of collection, fund and amount. Cancel in the system any OR cancelled on paper, with the reason.
          </li>
          <li>
            When a collector turns over collections, prepare and certify the collector&apos;s{" "}
            <Link href="/collections/rcr">RCR</Link>; the Treasurer acknowledges it.
          </li>
          <li>Record each deposit slip (bank, slip number, amount, fund) on the day of deposit.</li>
          <li>
            Prepare and certify the day&apos;s <Link href="/collections/rcd">RCD</Link>. Its total must equal the paper RCD.
          </li>
          <li>
            Enter each <Link href="/disbursements">Disbursement Voucher</Link> when it is prepared, with the same charges and
            deductions. Sign Boxes A, B and C in the system when they are signed on paper. Draw the check in the system with the
            same check number, and record Box D when the payee receives it.
          </li>
          <li>
            Before closing the day, compare the <Link href="/cashbook">Cashbook</Link> balances (Cash in Local Treasury and Cash
            in Bank) with the paper Cashbook. Write down any difference and its cause.
          </li>
        </ol>

        <h3 className="annex-section">After the month ends (Treasurer)</h3>
        <ol>
          <li>Give the RCDs to the Accountant by the 5th of the next month, as on paper.</li>
          <li>
            Prepare and certify the <Link href="/forms/raaf">RAAF</Link>. Its quantities and serial numbers must match the
            paper RAAF.
          </li>
          <li>
            Prepare and submit the <Link href="/disbursements/transmittal">Transmittal Letter</Link> within 10 days after
            month-end. Its list of DVs, checks, PB Certifications and RCDs must match the paper letter.
          </li>
          <li>Type the paper Cashbook totals into the form on this page, with notes on any difference.</li>
        </ol>

        <h3 className="annex-section">After the month ends (City/Municipal Accountant)</h3>
        <ol>
          <li>Acknowledge receipt of the Transmittal Letter in the system when the paper letter arrives.</li>
          <li>Post every certified RCD and every paid DV of the month to the Journal of Cash Transactions in the system.</li>
          <li>
            Compare the system&apos;s RCD and DV totals with the paper JCT entries for the month. They must agree peso for peso.
          </li>
          <li>Check that no OR or check number is missing or repeated: the RAAF ending serials must follow on from the issued ones.</li>
          <li>Review the comparison on this page and sign off when every figure agrees or every difference is explained.</li>
        </ol>

        <h3 className="annex-section">Still kept on paper only during this month</h3>
        <p>
          Cash advances, petty cash, payroll, the Registry of Appropriations and Obligations, bank debit and credit memos, and the
          bank reconciliation. These come in Phases 2 and 3.
        </p>
      </article>
    </>
  );
}
