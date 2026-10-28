import Link from "next/link";
import { notFound } from "next/navigation";
import { Flash } from "@/components/Flash";
import { PrintButton } from "@/components/PrintButton";
import { requireBarangay } from "@/lib/context";
import { MONTHS, formatAmount, formatDate, formatPeso, sum, todayManila } from "@/lib/format";
import { TL_STATUS } from "@/lib/labels";
import { addOtherReport, deleteOtherReport, deleteTransmittal, receiveTransmittal, submitTransmittal } from "../../actions";

type Tl = {
  id: string;
  tl_no: string | null;
  tl_date: string;
  period_year: number;
  period_month: number;
  status: string;
  submitted_at: string | null;
  received_by: string | null;
  received_at: string | null;
  barangay_id: string;
  treasurer: { full_name: string } | null;
  noted_by: { full_name: string } | null;
  barangay: { name: string; lgu: { name: string; lgu_type: string; province: string | null } | null } | null;
};
type DvRow = { id: string; dv_no: string; dv_date: string; payee: string };
type CheckRow = { dv_id: string; check_no: number; check_date: string; amount: string; pbc_no: string; pbc_date: string };
type RcdRow = { id: string; rcd_no: string | null; rcd_date: string };
type RcdTotal = { rcd_id: string; collections: string; deposits: string };
type RcrRow = { rcd_id: string; rcr_no: string | null };
type Other = { id: string; report_date: string; report_type: string };

export default async function TransmittalPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ ok?: string; error?: string }>;
}) {
  const { id } = await params;
  const { ok, error } = await searchParams;
  const { supabase, canWrite, isLguStaff } = await requireBarangay();

  const { data: tlRow } = await supabase
    .from("transmittal_letter")
    .select(
      "id, tl_no, tl_date, period_year, period_month, status, submitted_at, received_by, received_at, barangay_id, treasurer:treasurer_official_id(full_name), noted_by:noted_by_official_id(full_name), barangay:barangay_id(name, lgu:lgu_id(name, lgu_type, province))",
    )
    .eq("id", id)
    .maybeSingle();
  if (!tlRow) notFound();
  const tl = tlRow as unknown as Tl;

  const [{ data: dvRows }, { data: rcdRows }, { data: otherRows }] = await Promise.all([
    supabase.from("disbursement_voucher").select("id, dv_no, dv_date, payee").eq("transmittal_id", id).order("dv_no"),
    supabase.from("rcd").select("id, rcd_no, rcd_date").eq("transmittal_id", id).order("rcd_date"),
    supabase.from("tl_other_report").select("id, report_date, report_type").eq("transmittal_id", id).order("report_date"),
  ]);
  const dvs = (dvRows ?? []) as DvRow[];
  const rcds = (rcdRows ?? []) as RcdRow[];
  const others = (otherRows ?? []) as Other[];

  const [{ data: checkRows }, { data: rcdTotalRows }, { data: rcrRows }] = await Promise.all([
    dvs.length
      ? supabase.from("bank_check").select("dv_id, check_no, check_date, amount, pbc_no, pbc_date").in("dv_id", dvs.map((d) => d.id))
      : Promise.resolve({ data: [] as CheckRow[] }),
    rcds.length
      ? supabase.from("rcd_totals").select("rcd_id, collections, deposits").in("rcd_id", rcds.map((r) => r.id))
      : Promise.resolve({ data: [] as RcdTotal[] }),
    rcds.length
      ? supabase.from("rcr").select("rcd_id, rcr_no").in("rcd_id", rcds.map((r) => r.id)).order("rcr_no")
      : Promise.resolve({ data: [] as RcrRow[] }),
  ]);
  const checks = new Map(((checkRows ?? []) as CheckRow[]).map((c) => [c.dv_id, c]));
  const rcdTotals = new Map(((rcdTotalRows ?? []) as RcdTotal[]).map((t) => [t.rcd_id, t]));
  const rcrsOf = (rcdId: string) =>
    ((rcrRows ?? []) as RcrRow[]).filter((r) => r.rcd_id === rcdId).map((r) => r.rcr_no ?? "(draft)");

  const checkTotal = sum(dvs.map((d) => checks.get(d.id)?.amount));
  const rcdTotal = sum(rcds.map((r) => rcdTotals.get(r.id)?.collections));
  const lgu = tl.barangay?.lgu;
  const lguTitle = lgu?.lgu_type === "city" ? "City Accountant" : "Municipal Accountant";
  const monthName = `${MONTHS[tl.period_month - 1]} ${tl.period_year}`;
  const isDraft = tl.status === "draft";

  return (
    <>
      <header className="row no-print">
        <div>
          <h1>Transmittal Letter {tl.tl_no ?? "(draft)"}</h1>
          <p className="muted">
            <Link href="/disbursements/transmittal">All letters</Link> · {TL_STATUS[tl.status] ?? tl.status} · for {monthName}
          </p>
        </div>
        <div className="actions">
          <PrintButton />
          {canWrite && isDraft && (
            <>
              <form action={submitTransmittal}>
                <input type="hidden" name="id" value={tl.id} />
                <button type="submit">Submit to the Accountant (Treasurer)</button>
              </form>
              <form action={deleteTransmittal}>
                <input type="hidden" name="id" value={tl.id} />
                <button type="submit" className="secondary">Delete draft</button>
              </form>
            </>
          )}
        </div>
      </header>
      <Flash ok={ok} error={error} />

      {isLguStaff && tl.status === "submitted" && (
        <section className="card">
          <h2>Acknowledge receipt</h2>
          <form action={receiveTransmittal} className="inline-form">
            <input type="hidden" name="id" value={tl.id} />
            <input name="received_by" placeholder="Name of receiving staff" required size={32} />
            <button type="submit">Received (Accountant&apos;s office)</button>
          </form>
        </section>
      )}

      {canWrite && isDraft && (
        <section className="card">
          <h2>Other reports to transmit (section C)</h2>
          <form action={addOtherReport} className="inline-form">
            <input type="hidden" name="transmittal_id" value={tl.id} />
            <input name="report_date" type="date" required defaultValue={todayManila()} />
            <input name="report_type" placeholder="e.g. Report of Accountability for Accountable Forms" required size={40} />
            <button type="submit" className="secondary small">Add</button>
          </form>
        </section>
      )}

      <article className="annex">
        <div className="annex-tag">Annex 16</div>
        <h2 className="annex-title">TRANSMITTAL LETTER</h2>
        <div className="annex-head">
          <div>
            <div>Barangay: <u>{tl.barangay?.name}</u></div>
            <div>City/Municipality: <u>{lgu?.name}</u></div>
            <div>Province: <u>{lgu?.province ?? ""}</u></div>
          </div>
          <div>
            <div>TL No.: <u>{tl.tl_no ?? "—"}</u></div>
            <div>Date: <u>{formatDate(tl.tl_date)}</u></div>
          </div>
        </div>

        <p>
          To: The {lguTitle}
          <br />
          {lgu?.name}
          {lgu?.province ? `, ${lgu.province}` : ""}
        </p>
        <p>Sir/Madam:</p>
        <p>
          Submitted herewith are the following documents of Barangay {tl.barangay?.name} for the month of {monthName}:
        </p>

        <h3 className="annex-section">A. Disbursement Vouchers / Payrolls</h3>
        <table className="annex-table small">
          <thead>
            <tr>
              <th colSpan={2}>DV/Payroll</th>
              <th colSpan={2}>Check</th>
              <th rowSpan={2}>Payee</th>
              <th rowSpan={2} className="num">Amount</th>
              <th colSpan={2}>PB Certification</th>
            </tr>
            <tr>
              <th>Date</th><th>No.</th><th>Date</th><th>No.</th><th>Date</th><th>No.</th>
            </tr>
          </thead>
          <tbody>
            {dvs.map((d) => {
              const c = checks.get(d.id);
              return (
                <tr key={d.id}>
                  <td>{formatDate(d.dv_date)}</td>
                  <td>{d.dv_no}</td>
                  <td>{formatDate(c?.check_date)}</td>
                  <td>{c?.check_no ?? ""}</td>
                  <td>{d.payee}</td>
                  <td className="num">{formatAmount(c?.amount)}</td>
                  <td>{formatDate(c?.pbc_date)}</td>
                  <td>{c?.pbc_no ?? ""}</td>
                </tr>
              );
            })}
            {dvs.length === 0 && (
              <tr><td colSpan={8} className="muted">None</td></tr>
            )}
            <tr className="total"><td colSpan={5}>TOTAL</td><td className="num">{formatAmount(checkTotal)}</td><td colSpan={2}></td></tr>
          </tbody>
        </table>

        <h3 className="annex-section">B. Reports of Collections and Deposits and supporting documents (RCRs, ORs and deposit slips)</h3>
        <table className="annex-table small">
          <thead>
            <tr>
              <th>RCD Date</th>
              <th>RCD No.</th>
              <th>RCRs</th>
              <th className="num">Collections</th>
              <th className="num">Deposits</th>
            </tr>
          </thead>
          <tbody>
            {rcds.map((r) => (
              <tr key={r.id}>
                <td>{formatDate(r.rcd_date)}</td>
                <td>{r.rcd_no ?? ""}</td>
                <td>{rcrsOf(r.id).join(", ")}</td>
                <td className="num">{formatAmount(rcdTotals.get(r.id)?.collections)}</td>
                <td className="num">{formatAmount(rcdTotals.get(r.id)?.deposits)}</td>
              </tr>
            ))}
            {rcds.length === 0 && (
              <tr><td colSpan={5} className="muted">None</td></tr>
            )}
            <tr className="total">
              <td colSpan={3}>TOTAL</td>
              <td className="num">{formatAmount(rcdTotal)}</td>
              <td className="num">{formatAmount(sum(rcds.map((r) => rcdTotals.get(r.id)?.deposits)))}</td>
            </tr>
          </tbody>
        </table>

        <h3 className="annex-section">C. Other reports</h3>
        <table className="annex-table small">
          <thead>
            <tr>
              <th>Date</th>
              <th>Type of report</th>
              {canWrite && isDraft && <th className="no-print"></th>}
            </tr>
          </thead>
          <tbody>
            {others.map((o) => (
              <tr key={o.id}>
                <td>{formatDate(o.report_date)}</td>
                <td>{o.report_type}</td>
                {canWrite && isDraft && (
                  <td className="no-print">
                    <form action={deleteOtherReport}>
                      <input type="hidden" name="id" value={o.id} />
                      <input type="hidden" name="transmittal_id" value={tl.id} />
                      <button type="submit" className="secondary small">Remove</button>
                    </form>
                  </td>
                )}
              </tr>
            ))}
            {others.length === 0 && (
              <tr><td colSpan={canWrite && isDraft ? 3 : 2} className="muted">None</td></tr>
            )}
          </tbody>
        </table>

        <div className="sig-row">
          <div className="sig">
            <div>Very truly yours,</div>
            <div className="sig-line">{tl.treasurer?.full_name ?? ""}</div>
            <div className="sig-label">Barangay Treasurer</div>
          </div>
          <div className="sig">
            <div>Noted by:</div>
            <div className="sig-line">{tl.noted_by?.full_name ?? ""}</div>
            <div className="sig-label">Punong Barangay</div>
          </div>
        </div>
        <div className="sig-row">
          <div className="sig">
            <div>Received by:</div>
            <div className="sig-line">{tl.received_by ?? ""}</div>
            <div className="sig-label">
              Office of the {lguTitle} · Date: {tl.received_at ? formatDate(tl.received_at.slice(0, 10)) : "____________"}
            </div>
          </div>
        </div>
      </article>

      <p className="muted no-print">
        {dvs.length} DVs for {formatPeso(checkTotal)} · {rcds.length} RCDs for {formatPeso(rcdTotal)}
        {tl.submitted_at ? ` · submitted ${formatDate(tl.submitted_at.slice(0, 10))}` : ""}
      </p>
    </>
  );
}
