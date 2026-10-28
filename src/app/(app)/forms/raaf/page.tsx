import Link from "next/link";
import { Flash } from "@/components/Flash";
import { requireBarangay } from "@/lib/context";
import { MONTHS, formatDate, todayManila } from "@/lib/format";
import { prepareRaaf } from "../actions";

type RaafRow = { id: string; raaf_no: string | null; period_year: number; period_month: number; status: string; certified_at: string | null };

export default async function RaafListPage({ searchParams }: { searchParams: Promise<{ ok?: string; error?: string }> }) {
  const { ok, error } = await searchParams;
  const { supabase, barangay, canWrite } = await requireBarangay();
  const today = todayManila();
  // Default to last month: the RAAF goes to the Accountant within 10 days after month-end.
  const prev = new Date(Date.UTC(Number(today.slice(0, 4)), Number(today.slice(5, 7)) - 2, 1));

  const { data: rows } = await supabase
    .from("raaf")
    .select("id, raaf_no, period_year, period_month, status, certified_at")
    .eq("barangay_id", barangay.id)
    .order("period_year", { ascending: false })
    .order("period_month", { ascending: false })
    .limit(60);
  const reports = (rows ?? []) as RaafRow[];

  return (
    <>
      <header className="row">
        <div>
          <h1>Report of Accountability for Accountable Forms</h1>
          <p className="muted">
            {barangay.name} · Annex 18 · one report a month for every booklet of cash tickets, Official Receipts and checks ·{" "}
            <Link href="/forms">Booklets</Link>
          </p>
        </div>
      </header>
      <Flash ok={ok} error={error} />

      {canWrite && (
        <section className="card">
          <h2>Prepare a RAAF</h2>
          <p className="muted">
            The balances are worked out from the booklets recorded and the receipts and checks issued. The Treasurer certifies the
            report from the last day of the month; it is then numbered and final.
          </p>
          <form action={prepareRaaf} className="grid">
            <input type="hidden" name="barangay_id" value={barangay.id} />
            <label>
              Month
              <select name="month" defaultValue={prev.getUTCMonth() + 1}>
                {MONTHS.map((m, i) => (
                  <option key={m} value={i + 1}>
                    {m}
                  </option>
                ))}
              </select>
            </label>
            <label>
              Year
              <input name="year" type="number" min={2000} max={2100} defaultValue={prev.getUTCFullYear()} required />
            </label>
            <div className="span2">
              <button type="submit">Prepare draft RAAF</button>
            </div>
          </form>
        </section>
      )}

      <section className="card">
        <h2>Reports</h2>
        {reports.length === 0 ? (
          <p className="muted">No RAAFs yet.</p>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>RAAF No.</th>
                  <th>For the month of</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                {reports.map((r) => (
                  <tr key={r.id}>
                    <td>
                      <Link href={`/forms/raaf/${r.id}`}>{r.raaf_no ?? "(draft)"}</Link>
                    </td>
                    <td>
                      {MONTHS[r.period_month - 1]} {r.period_year}
                    </td>
                    <td>{r.status === "certified" ? `Certified ${formatDate(r.certified_at?.slice(0, 10))}` : "Draft"}</td>
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
