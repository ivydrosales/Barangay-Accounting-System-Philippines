import Link from "next/link";
import { notFound } from "next/navigation";
import { Flash } from "@/components/Flash";
import { PrintButton } from "@/components/PrintButton";
import { requireBarangay } from "@/lib/context";
import { formatAmount, formatDate, formatPeso, sum } from "@/lib/format";
import { AccountableForms, type AccountableFormRow } from "@/components/AccountableForms";
import { certifyRcd, deleteDeposit, deleteRcd, postRcd } from "../../actions";

type Rcd = {
  id: string;
  rcd_no: string | null;
  rcd_date: string;
  status: string;
  certified_at: string | null;
  posted_at: string | null;
  barangay_id: string;
  treasurer: { full_name: string } | null;
  barangay: { name: string } | null;
};
type Line = { line_date: string; number: string; payor: string; nature: string; amount: string | null; is_cancelled: boolean; kind: string; ref_id: string };
type DepositRow = { id: string; deposit_date: string; reference: string; amount: string; bank: { bank_name: string; branch: string | null } | null };
type FormRow = AccountableFormRow;
type EntryLine = { line_no: number; account_code: string; debit: string; credit: string; account: { title: string } | null; entry: { entry_no: string; description: string } | null };

export default async function RcdPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ ok?: string; error?: string }>;
}) {
  const { id } = await params;
  const { ok, error } = await searchParams;
  const { supabase, canWrite, isLguStaff } = await requireBarangay();

  const { data: rcdRow } = await supabase
    .from("rcd")
    .select("id, rcd_no, rcd_date, status, certified_at, posted_at, barangay_id, treasurer:treasurer_official_id(full_name), barangay:barangay_id(name)")
    .eq("id", id)
    .maybeSingle();
  if (!rcdRow) notFound();
  const rcd = rcdRow as unknown as Rcd;

  const [{ data: lineRows }, { data: depositRows }, { data: formRows }, { data: entryRows }] = await Promise.all([
    supabase.rpc("rcd_collection_lines", { p_rcd: id }),
    supabase
      .from("deposit")
      .select("id, deposit_date, reference, amount, bank:bank_account_id(bank_name, branch)")
      .eq("rcd_id", id)
      .order("deposit_date"),
    supabase.rpc("report_accountable_forms", { p_barangay: rcd.barangay_id, p_date: rcd.rcd_date }),
    supabase
      .from("journal_line")
      .select("line_no, account_code, debit, credit, account:account_code(title), entry:entry_id!inner(entry_no, description, source_id)")
      .eq("entry.source_id", id)
      .order("line_no"),
  ]);
  const lines = (lineRows ?? []) as Line[];
  const deposits = (depositRows ?? []) as unknown as DepositRow[];
  const forms = (formRows ?? []) as FormRow[];
  const entryLines = (entryRows ?? []) as unknown as EntryLine[];
  const collections = sum(lines.map((l) => l.amount));
  const depositTotal = sum(deposits.map((d) => d.amount));

  return (
    <>
      <header className="row no-print">
        <div>
          <h1>RCD {rcd.rcd_no ?? "(draft)"}</h1>
          <p className="muted">
            <Link href="/collections/rcd">All RCDs</Link> · {rcd.status === "draft" ? "Draft" : rcd.status === "certified" ? "Certified, awaiting posting by the Accountant" : "Posted to the JCT"}
          </p>
        </div>
        <div className="actions">
          <PrintButton />
          {canWrite && rcd.status === "draft" && (
            <>
              <form action={certifyRcd}>
                <input type="hidden" name="id" value={rcd.id} />
                <button type="submit">Certify (Treasurer)</button>
              </form>
              <form action={deleteRcd}>
                <input type="hidden" name="id" value={rcd.id} />
                <button type="submit" className="secondary">Delete draft</button>
              </form>
            </>
          )}
          {isLguStaff && rcd.status === "certified" && (
            <form action={postRcd}>
              <input type="hidden" name="id" value={rcd.id} />
              <button type="submit">Post to JCT (Accountant)</button>
            </form>
          )}
        </div>
      </header>
      <Flash ok={ok} error={error} />

      <article className="annex">
        <div className="annex-tag">Annex 9</div>
        <h2 className="annex-title">REPORT OF COLLECTIONS AND DEPOSITS</h2>
        <div className="annex-head">
          <div>
            <div>Name of Barangay Treasurer: <u>{rcd.treasurer?.full_name ?? "—"}</u></div>
            <div>Barangay: <u>{rcd.barangay?.name}</u></div>
          </div>
          <div>
            <div>Date: <u>{formatDate(rcd.rcd_date)}</u></div>
            <div>RCD No.: <u>{rcd.rcd_no ?? "—"}</u></div>
          </div>
        </div>

        <h3 className="annex-section">A. COLLECTIONS</h3>
        <table className="annex-table">
          <thead>
            <tr>
              <th colSpan={2}>Official Receipt/RCR</th>
              <th rowSpan={2}>Payor/DBC</th>
              <th rowSpan={2}>Nature of Collection</th>
              <th rowSpan={2} className="num">Amounts</th>
            </tr>
            <tr><th>Date</th><th>Number</th></tr>
          </thead>
          <tbody>
            {lines.map((l) => (
              <tr key={l.ref_id}>
                <td>{formatDate(l.line_date)}</td>
                <td>{l.number}</td>
                <td>{l.is_cancelled ? "CANCELLED" : l.payor}</td>
                <td>{l.is_cancelled ? "" : l.nature}</td>
                <td className="num">{formatAmount(l.amount)}</td>
              </tr>
            ))}
            <tr className="total"><td colSpan={4}>TOTAL</td><td className="num">{formatAmount(collections)}</td></tr>
          </tbody>
        </table>

        <h3 className="annex-section">B. DEPOSITS</h3>
        <table className="annex-table">
          <thead>
            <tr><th>Bank/Branch</th><th>Reference</th><th className="num">Amount</th>{canWrite && rcd.status === "draft" && <th className="no-print"></th>}</tr>
          </thead>
          <tbody>
            {deposits.map((d) => (
              <tr key={d.id}>
                <td>{d.bank?.bank_name}{d.bank?.branch ? ` / ${d.bank.branch}` : ""}</td>
                <td>{d.reference} · {formatDate(d.deposit_date)}</td>
                <td className="num">{formatAmount(d.amount)}</td>
                {canWrite && rcd.status === "draft" && (
                  <td className="no-print">
                    <form action={deleteDeposit}>
                      <input type="hidden" name="id" value={d.id} />
                      <input type="hidden" name="return_to" value={`/collections/rcd/${rcd.id}`} />
                      <button type="submit" className="secondary small">Remove</button>
                    </form>
                  </td>
                )}
              </tr>
            ))}
            <tr className="total"><td colSpan={2}>TOTAL</td><td className="num">{formatAmount(depositTotal)}</td>{canWrite && rcd.status === "draft" && <td className="no-print"></td>}</tr>
          </tbody>
        </table>

        <h3 className="annex-section">C. ACCOUNTABILITY FOR ACCOUNTABLE FORMS</h3>
        <AccountableForms rows={forms} />

        <div className="annex-box">
          <h3 className="annex-section">D. CERTIFICATION</h3>
          <p>I hereby certify that this Report of Collections and Deposits, and Accountable Forms including supporting documents are true and correct.</p>
          <div className="sig-row">
            <div className="sig">
              <div className="sig-line">{rcd.treasurer?.full_name ?? ""}</div>
              <div className="sig-label">Barangay Treasurer</div>
            </div>
            <div className="sig">
              <div className="sig-line">{rcd.certified_at ? formatDate(rcd.certified_at.slice(0, 10)) : ""}</div>
              <div className="sig-label">Date</div>
            </div>
          </div>
        </div>

        <h3 className="annex-section">E. ACCOUNTING ENTRIES</h3>
        <table className="annex-table">
          <thead>
            <tr><th>Account Title</th><th>Account Code</th><th className="num">Debit</th><th className="num">Credit</th></tr>
          </thead>
          <tbody>
            {entryLines.length === 0 ? (
              <tr><td colSpan={4} className="muted">Prepared by the Barangay Bookkeeper and approved by the C/M Accountant when this report is posted.</td></tr>
            ) : (
              entryLines.map((l, i) => (
                <tr key={i}>
                  <td className={Number(l.credit) > 0 ? "indent" : undefined}>{l.account?.title}</td>
                  <td>{l.account_code}</td>
                  <td className="num">{formatAmount(l.debit)}</td>
                  <td className="num">{formatAmount(l.credit)}</td>
                </tr>
              ))
            )}
          </tbody>
        </table>
        <div className="sig-row">
          <div>Prepared by: ______________________</div>
          <div>Approved by: ______________________</div>
        </div>
      </article>

      <p className="muted no-print">
        Collections {formatPeso(collections)} · Deposits {formatPeso(depositTotal)}
        {rcd.posted_at ? ` · Posted ${formatDate(rcd.posted_at.slice(0, 10))}` : ""}
      </p>
    </>
  );
}
