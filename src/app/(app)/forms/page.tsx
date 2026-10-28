import Link from "next/link";
import { Flash } from "@/components/Flash";
import { requireBarangay } from "@/lib/context";
import { formatDate, todayManila } from "@/lib/format";
import { FORM_STATUS, FORM_TYPE } from "@/lib/labels";
import { addBooklet, setBookletStatus } from "./actions";

type Official = { id: string; full_name: string; position: string };
type Booklet = {
  id: string;
  form_type: string;
  form_name: string;
  series: string | null;
  serial_from: number;
  serial_to: number;
  next_serial: number;
  received_on: string | null;
  status: string;
  issued_to: { full_name: string } | null;
};

export default async function FormsPage({ searchParams }: { searchParams: Promise<{ ok?: string; error?: string }> }) {
  const { ok, error } = await searchParams;
  const { supabase, barangay, canWrite } = await requireBarangay();

  const [{ data: officialRows }, { data: bookletRows }] = await Promise.all([
    supabase.from("official").select("id, full_name, position").eq("barangay_id", barangay.id).eq("is_active", true).order("full_name"),
    supabase
      .from("accountable_form")
      .select("id, form_type, form_name, series, serial_from, serial_to, next_serial, received_on, status, issued_to:issued_to_official_id(full_name)")
      .eq("barangay_id", barangay.id)
      .order("form_type")
      .order("serial_from"),
  ]);
  const officials = (officialRows ?? []) as Official[];
  const booklets = (bookletRows ?? []) as unknown as Booklet[];

  return (
    <>
      <header className="row">
        <div>
          <h1>Accountable forms</h1>
          <p className="muted">
            {barangay.name} · booklets of Official Receipts, cash tickets and checks. Each serial is issued once, in order; the
            Treasurer reports them monthly on the <Link href="/forms/raaf">Report of Accountability for Accountable Forms</Link>{" "}
            (RAAF, Annex 18).
          </p>
        </div>
      </header>
      <Flash ok={ok} error={error} />

      {canWrite && (
        <section className="card">
          <h2>Record a booklet</h2>
          <form action={addBooklet} className="grid">
            <input type="hidden" name="lgu_id" value={barangay.lgu_id} />
            <input type="hidden" name="barangay_id" value={barangay.id} />
            <label>
              Kind
              <select name="form_type" required defaultValue="official_receipt">
                {Object.entries(FORM_TYPE).map(([k, v]) => (
                  <option key={k} value={k}>
                    {v}
                  </option>
                ))}
              </select>
            </label>
            <label>
              Booklet or stub No.
              <input name="series" placeholder="As printed on the booklet" />
            </label>
            <label>
              First serial
              <input name="serial_from" type="number" min={1} required />
            </label>
            <label>
              Last serial
              <input name="serial_to" type="number" min={1} required />
            </label>
            <label>
              Received on
              <input name="received_on" type="date" defaultValue={todayManila()} />
            </label>
            <label>
              Issued to
              <select name="issued_to_official_id" defaultValue="">
                <option value="">Barangay Treasurer (default)</option>
                {officials.map((o) => (
                  <option key={o.id} value={o.id}>
                    {o.full_name} · {o.position}
                  </option>
                ))}
              </select>
            </label>
            <div className="span2">
              <button type="submit">Record booklet</button>
            </div>
          </form>
        </section>
      )}

      <section className="card">
        <h2>Booklets</h2>
        {booklets.length === 0 ? (
          <p className="muted">No booklets recorded yet.</p>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Kind</th>
                  <th>Booklet</th>
                  <th>Serials</th>
                  <th>Next</th>
                  <th>Issued to</th>
                  <th>Received</th>
                  <th>Status</th>
                  {canWrite && <th></th>}
                </tr>
              </thead>
              <tbody>
                {booklets.map((b) => (
                  <tr key={b.id}>
                    <td>{FORM_TYPE[b.form_type] ?? b.form_type}</td>
                    <td>{b.series ?? b.form_name}</td>
                    <td>
                      {b.serial_from}–{b.serial_to}
                    </td>
                    <td>{b.next_serial > b.serial_to ? "used up" : b.next_serial}</td>
                    <td>{b.issued_to?.full_name ?? ""}</td>
                    <td>{formatDate(b.received_on)}</td>
                    <td>{FORM_STATUS[b.status] ?? b.status}</td>
                    {canWrite && (
                      <td>
                        {["on_hand", "in_use"].includes(b.status) && (
                          <form action={setBookletStatus} className="inline-form">
                            <input type="hidden" name="id" value={b.id} />
                            <select name="status" defaultValue="returned" aria-label="New status">
                              <option value="returned">Returned</option>
                              <option value="lost">Lost</option>
                            </select>
                            <button type="submit" className="secondary small">
                              Mark
                            </button>
                          </form>
                        )}
                      </td>
                    )}
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
