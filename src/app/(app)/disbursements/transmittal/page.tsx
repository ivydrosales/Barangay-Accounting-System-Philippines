import Link from "next/link";
import { Flash } from "@/components/Flash";
import { requireBarangay } from "@/lib/context";
import { MONTHS, formatDate, todayManila } from "@/lib/format";
import { TL_STATUS } from "@/lib/labels";
import { prepareTransmittal } from "../actions";

type TlRow = {
  id: string;
  tl_no: string | null;
  tl_date: string;
  period_year: number;
  period_month: number;
  status: string;
  received_by: string | null;
};
type Ref = { transmittal_id: string };

export default async function TransmittalListPage({ searchParams }: { searchParams: Promise<{ ok?: string; error?: string }> }) {
  const { ok, error } = await searchParams;
  const { supabase, barangay, canWrite } = await requireBarangay();
  const today = todayManila();
  // Default to last month: the TL goes to the Accountant within 10 days after month-end.
  const prev = new Date(Date.UTC(Number(today.slice(0, 4)), Number(today.slice(5, 7)) - 2, 1));
  const defaultYear = prev.getUTCFullYear();
  const defaultMonth = prev.getUTCMonth() + 1;

  const { data: rows } = await supabase
    .from("transmittal_letter")
    .select("id, tl_no, tl_date, period_year, period_month, status, received_by")
    .eq("barangay_id", barangay.id)
    .order("period_year", { ascending: false })
    .order("period_month", { ascending: false })
    .limit(60);
  const tls = (rows ?? []) as TlRow[];
  const ids = tls.map((t) => t.id);
  const [{ data: dvRefs }, { data: rcdRefs }] = ids.length
    ? await Promise.all([
        supabase.from("disbursement_voucher").select("transmittal_id").in("transmittal_id", ids),
        supabase.from("rcd").select("transmittal_id").in("transmittal_id", ids),
      ])
    : [{ data: [] as Ref[] }, { data: [] as Ref[] }];
  const count = (refs: Ref[] | null, id: string) => (refs ?? []).filter((r) => r.transmittal_id === id).length;

  return (
    <>
      <header className="row">
        <div>
          <h1>Transmittal Letters</h1>
          <p className="muted">
            {barangay.name} · Annex 16 · the Treasurer sends the month&apos;s paid DVs, checks, PB Certifications and RCDs to the
            City/Municipal Accountant within 10 days after month-end
          </p>
        </div>
      </header>
      <Flash ok={ok} error={error} />

      {canWrite && (
        <section className="card">
          <h2>Prepare a Transmittal Letter</h2>
          <p className="muted">Gathers every paid DV (by check date) and certified RCD of the month that is not yet on a letter.</p>
          <form action={prepareTransmittal} className="grid">
            <input type="hidden" name="barangay_id" value={barangay.id} />
            <label>
              Month
              <select name="month" defaultValue={defaultMonth}>
                {MONTHS.map((m, i) => (
                  <option key={m} value={i + 1}>
                    {m}
                  </option>
                ))}
              </select>
            </label>
            <label>
              Year
              <input name="year" type="number" min={2000} max={2100} defaultValue={defaultYear} required />
            </label>
            <label>
              Letter date
              <input name="tl_date" type="date" defaultValue={today} />
            </label>
            <div className="span2">
              <button type="submit">Prepare draft letter</button>
            </div>
          </form>
        </section>
      )}

      <section className="card">
        <h2>Letters</h2>
        {tls.length === 0 ? (
          <p className="muted">No Transmittal Letters yet.</p>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>TL No.</th>
                  <th>Date</th>
                  <th>For the month of</th>
                  <th className="num">DVs</th>
                  <th className="num">RCDs</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                {tls.map((t) => (
                  <tr key={t.id}>
                    <td>
                      <Link href={`/disbursements/transmittal/${t.id}`}>{t.tl_no ?? "(draft)"}</Link>
                    </td>
                    <td>{formatDate(t.tl_date)}</td>
                    <td>
                      {MONTHS[t.period_month - 1]} {t.period_year}
                    </td>
                    <td className="num">{count(dvRefs as Ref[], t.id)}</td>
                    <td className="num">{count(rcdRefs as Ref[], t.id)}</td>
                    <td>
                      {TL_STATUS[t.status] ?? t.status}
                      {t.received_by ? ` (${t.received_by})` : ""}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </>
  );
}
