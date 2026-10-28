import Link from "next/link";
import { notFound } from "next/navigation";
import { AccountableForms, type AccountableFormRow } from "@/components/AccountableForms";
import { Flash } from "@/components/Flash";
import { PrintButton } from "@/components/PrintButton";
import { requireBarangay } from "@/lib/context";
import { formatAmount, formatDate, formatPeso, sum } from "@/lib/format";
import { acknowledgeRcr, certifyRcr, deleteRcr } from "../../actions";

type Rcr = {
  id: string;
  rcr_no: string | null;
  rcr_date: string;
  status: string;
  beginning_balance: string;
  certified_at: string | null;
  acknowledged_at: string | null;
  barangay_id: string;
  collector: { id: string; full_name: string } | null;
  barangay: { name: string; lgu: { name: string; province: string | null } | null } | null;
};
type OrRow = {
  id: string;
  serial_no: number;
  or_date: string;
  payor: string;
  nature: string;
  amount: string;
  status: string;
  payment_mode: string;
  check_no: string | null;
};
type FormRow = AccountableFormRow;

export default async function RcrPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ ok?: string; error?: string }>;
}) {
  const { id } = await params;
  const { ok, error } = await searchParams;
  const { supabase, canWrite } = await requireBarangay();

  const { data: rcrRow } = await supabase
    .from("rcr")
    .select(
      "id, rcr_no, rcr_date, status, beginning_balance, certified_at, acknowledged_at, barangay_id, collector:collector_official_id(id, full_name), barangay:barangay_id(name, lgu:lgu_id(name, province))",
    )
    .eq("id", id)
    .maybeSingle();
  if (!rcrRow) notFound();
  const rcr = rcrRow as unknown as Rcr;

  const [{ data: orRows }, { data: formRows }, { data: treasurer }] = await Promise.all([
    supabase
      .from("official_receipt")
      .select("id, serial_no, or_date, payor, nature, amount, status, payment_mode, check_no")
      .eq("rcr_id", id)
      .order("or_date")
      .order("serial_no"),
    supabase.rpc("report_accountable_forms", { p_barangay: rcr.barangay_id, p_date: rcr.rcr_date, p_collector: rcr.collector?.id }),
    supabase
      .from("official")
      .select("full_name")
      .eq("barangay_id", rcr.barangay_id)
      .eq("position", "Barangay Treasurer")
      .eq("is_active", true)
      .limit(1)
      .maybeSingle(),
  ]);
  const ors = (orRows ?? []) as OrRow[];
  const forms = (formRows ?? []) as FormRow[];
  const issued = ors.filter((o) => o.status === "issued");
  const cash = sum(issued.filter((o) => o.payment_mode === "cash").map((o) => o.amount));
  const checks = issued.filter((o) => o.payment_mode === "check");
  const checkTotal = sum(checks.map((o) => o.amount));
  const total = cash + checkTotal;

  return (
    <>
      <header className="row no-print">
        <div>
          <h1>RCR {rcr.rcr_no ?? "(draft)"}</h1>
          <p className="muted">
            <Link href="/collections/rcr">All RCRs</Link> · {rcr.status === "draft" ? "Draft" : rcr.status === "certified" ? "Certified, awaiting the Treasurer" : "Acknowledged"}
          </p>
        </div>
        <div className="actions">
          <PrintButton />
          {canWrite && rcr.status === "draft" && (
            <>
              <form action={certifyRcr}>
                <input type="hidden" name="id" value={rcr.id} />
                <button type="submit">Certify (collector)</button>
              </form>
              <form action={deleteRcr}>
                <input type="hidden" name="id" value={rcr.id} />
                <button type="submit" className="secondary">Delete draft</button>
              </form>
            </>
          )}
          {canWrite && rcr.status === "certified" && (
            <form action={acknowledgeRcr}>
              <input type="hidden" name="id" value={rcr.id} />
              <button type="submit">Acknowledge receipt (Treasurer)</button>
            </form>
          )}
        </div>
      </header>
      <Flash ok={ok} error={error} />

      <article className="annex">
        <div className="annex-tag">Annex 9.1</div>
        <h2 className="annex-title">REPORT OF COLLECTIONS AND REMITTANCES</h2>
        <div className="annex-head">
          <div>
            <div>Name of Collecting Officer: <u>{rcr.collector?.full_name}</u></div>
            <div>Barangay: <u>{rcr.barangay?.name}</u></div>
            <div>City/Municipality: <u>{rcr.barangay?.lgu?.name}</u></div>
            <div>Province: <u>{rcr.barangay?.lgu?.province ?? ""}</u></div>
          </div>
          <div>
            <div>Date: <u>{formatDate(rcr.rcr_date)}</u></div>
            <div>RCR No.: <u>{rcr.rcr_no ?? "—"}</u></div>
          </div>
        </div>

        <h3 className="annex-section">A. COLLECTIONS</h3>
        <table className="annex-table">
          <thead>
            <tr>
              <th colSpan={2}>Official Receipt</th>
              <th rowSpan={2}>Payor</th>
              <th rowSpan={2}>Nature of Collection</th>
              <th rowSpan={2} className="num">Amount</th>
            </tr>
            <tr>
              <th>Date</th>
              <th>Number</th>
            </tr>
          </thead>
          <tbody>
            {ors.map((o) => (
              <tr key={o.id}>
                <td>{formatDate(o.or_date)}</td>
                <td>{o.serial_no}</td>
                <td>{o.status === "cancelled" ? "CANCELLED" : o.payor}</td>
                <td>{o.status === "cancelled" ? "" : o.nature}</td>
                <td className="num">{o.status === "cancelled" ? "" : formatAmount(o.amount)}</td>
              </tr>
            ))}
            <tr className="total">
              <td colSpan={4}>TOTAL</td>
              <td className="num">{formatAmount(total)}</td>
            </tr>
          </tbody>
        </table>

        <h3 className="annex-section">B. SUMMARY OF COLLECTIONS</h3>
        <div className="annex-two">
          <table className="annex-table">
            <tbody>
              <tr><td>Beginning Balance</td><td className="num">{formatAmount(rcr.beginning_balance)}</td></tr>
              <tr><td>Add: Collections – Cash</td><td className="num">{formatAmount(cash)}</td></tr>
              <tr><td>Collections – Checks</td><td className="num">{formatAmount(checkTotal)}</td></tr>
              <tr className="total"><td>Total</td><td className="num">{formatAmount(Number(rcr.beginning_balance) + total)}</td></tr>
            </tbody>
          </table>
          <table className="annex-table">
            <thead>
              <tr><th colSpan={3}>List of Checks</th></tr>
              <tr><th>Check No.</th><th>Payee</th><th className="num">Amount</th></tr>
            </thead>
            <tbody>
              {checks.length === 0 ? (
                <tr><td colSpan={3} className="muted">None</td></tr>
              ) : (
                checks.map((c) => (
                  <tr key={c.id}><td>{c.check_no}</td><td>{c.payor}</td><td className="num">{formatAmount(c.amount)}</td></tr>
                ))
              )}
            </tbody>
          </table>
        </div>

        <h3 className="annex-section">C. ACCOUNTABILITY FOR ACCOUNTABLE FORMS</h3>
        <AccountableForms rows={forms} />

        <div className="annex-two">
          <div className="annex-box">
            <h3 className="annex-section">D. CERTIFICATION</h3>
            <p>I hereby certify that this Report of Collections and Remittances, and Accountable Forms including supporting documents are true and correct.</p>
            <div className="sig">
              <div className="sig-line">{rcr.collector?.full_name}</div>
              <div className="sig-label">Deputized Barangay Collector</div>
              <div className="sig-date">Date: {rcr.certified_at ? formatDate(rcr.certified_at.slice(0, 10)) : "____________"}</div>
            </div>
          </div>
          <div className="annex-box">
            <h3 className="annex-section">E. ACKNOWLEDGEMENT</h3>
            <p>I hereby certify that the foregoing Report of Collections and Remittances and Accountable Forms including cash and supporting documents have been received.</p>
            <div className="sig">
              <div className="sig-line">{treasurer?.full_name ?? ""}</div>
              <div className="sig-label">Barangay Treasurer</div>
              <div className="sig-date">Date: {rcr.acknowledged_at ? formatDate(rcr.acknowledged_at.slice(0, 10)) : "____________"}</div>
            </div>
          </div>
        </div>
      </article>

      <p className="muted no-print">Total collections: {formatPeso(total)}</p>
    </>
  );
}

