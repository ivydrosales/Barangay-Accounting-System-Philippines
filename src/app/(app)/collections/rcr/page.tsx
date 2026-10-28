import Link from "next/link";
import { Flash } from "@/components/Flash";
import { requireBarangay } from "@/lib/context";
import { formatDate, formatPeso, todayManila } from "@/lib/format";
import { prepareRcr } from "../actions";

type Official = { id: string; full_name: string; position: string };
type RcrRow = {
  id: string;
  rcr_no: string | null;
  rcr_date: string;
  status: string;
  collector: { full_name: string } | null;
  rcd: { rcd_no: string | null } | null;
};
type Totals = { rcr_id: string; total: string; or_count: number };

const STATUS: Record<string, string> = {
  draft: "Draft",
  certified: "Certified by collector",
  acknowledged: "Acknowledged by Treasurer",
};

export default async function RcrListPage({ searchParams }: { searchParams: Promise<{ ok?: string; error?: string }> }) {
  const { ok, error } = await searchParams;
  const { supabase, barangay, canWrite } = await requireBarangay();

  const [{ data: officials }, { data: rows }] = await Promise.all([
    supabase
      .from("official")
      .select("id, full_name, position")
      .eq("barangay_id", barangay.id)
      .eq("is_active", true)
      .neq("position", "Barangay Treasurer")
      .order("full_name"),
    supabase
      .from("rcr")
      .select("id, rcr_no, rcr_date, status, collector:collector_official_id(full_name), rcd:rcd_id(rcd_no)")
      .eq("barangay_id", barangay.id)
      .order("rcr_date", { ascending: false })
      .limit(100),
  ]);
  const rcrs = (rows ?? []) as unknown as RcrRow[];
  const { data: totalRows } = rcrs.length
    ? await supabase.from("rcr_totals").select("rcr_id, total, or_count").in("rcr_id", rcrs.map((r) => r.id))
    : { data: [] as Totals[] };
  const totals = new Map(((totalRows ?? []) as Totals[]).map((t) => [t.rcr_id, t]));

  return (
    <>
      <header className="row">
        <div>
          <h1>Report of Collections and Remittances</h1>
          <p className="muted">{barangay.name} · Annex 9.1 · the collector&apos;s daily report, turned over to the Treasurer</p>
        </div>
      </header>
      <Flash ok={ok} error={error} />

      {canWrite && (
        <section className="card">
          <h2>Prepare an RCR</h2>
          <p className="muted">
            Gathers every unreported OR of the collector dated on or before the report date.
          </p>
          <form action={prepareRcr} className="grid">
            <input type="hidden" name="barangay_id" value={barangay.id} />
            <label>
              Collecting officer
              <select name="collector_id" required>
                {((officials ?? []) as Official[]).map((o) => (
                  <option key={o.id} value={o.id}>
                    {o.full_name} · {o.position}
                  </option>
                ))}
              </select>
            </label>
            <label>
              Report date
              <input name="rcr_date" type="date" required defaultValue={todayManila()} />
            </label>
            <div className="span2">
              <button type="submit">Prepare draft RCR</button>
            </div>
          </form>
        </section>
      )}

      <section className="card">
        <h2>Reports</h2>
        {rcrs.length === 0 ? (
          <p className="muted">No RCRs yet.</p>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>RCR No.</th>
                  <th>Date</th>
                  <th>Collecting officer</th>
                  <th className="num">ORs</th>
                  <th className="num">Total</th>
                  <th>Status</th>
                  <th>On RCD</th>
                </tr>
              </thead>
              <tbody>
                {rcrs.map((r) => (
                  <tr key={r.id}>
                    <td>
                      <Link href={`/collections/rcr/${r.id}`}>{r.rcr_no ?? "(draft)"}</Link>
                    </td>
                    <td>{formatDate(r.rcr_date)}</td>
                    <td>{r.collector?.full_name}</td>
                    <td className="num">{totals.get(r.id)?.or_count ?? 0}</td>
                    <td className="num">{formatPeso(totals.get(r.id)?.total ?? 0)}</td>
                    <td>{STATUS[r.status] ?? r.status}</td>
                    <td>{r.rcd ? `RCD ${r.rcd.rcd_no ?? "(draft)"}` : ""}</td>
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
