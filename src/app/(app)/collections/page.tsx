import { Flash } from "@/components/Flash";
import { requireBarangay } from "@/lib/context";
import { formatDate, formatPeso, todayManila } from "@/lib/format";
import { cancelOr, issueOr } from "./actions";

type Booklet = { id: string; series: string | null; serial_from: number; serial_to: number; next_serial: number; status: string };
type CollectionType = { id: string; name: string };
type Fund = { id: string; code: string; name: string };
type OrRow = {
  id: string;
  serial_no: number;
  or_date: string;
  payor: string;
  nature: string;
  amount: string;
  payment_mode: string;
  check_bank: string | null;
  check_no: string | null;
  status: string;
  cancelled_reason: string | null;
  fund: { code: string } | null;
  rcd: { rcd_no: string | null; status: string } | null;
  rcr: { rcr_no: string | null; status: string } | null;
};

export default async function CollectionsPage({ searchParams }: { searchParams: Promise<{ ok?: string; error?: string }> }) {
  const { ok, error } = await searchParams;
  const { supabase, barangay, canWrite } = await requireBarangay();

  const [{ data: booklets }, { data: types }, { data: funds }, { data: orRows }] = await Promise.all([
    supabase
      .from("accountable_form")
      .select("id, series, serial_from, serial_to, next_serial, status")
      .eq("barangay_id", barangay.id)
      .eq("form_type", "official_receipt")
      .in("status", ["on_hand", "in_use"])
      .order("serial_from"),
    supabase.from("collection_type").select("id, name").eq("lgu_id", barangay.lgu_id).eq("is_active", true).order("name"),
    supabase.from("fund").select("id, code, name").eq("barangay_id", barangay.id).eq("is_active", true).order("code"),
    supabase
      .from("official_receipt")
      .select(
        "id, serial_no, or_date, payor, nature, amount, payment_mode, check_bank, check_no, status, cancelled_reason, fund:fund_id(code), rcd:rcd_id(rcd_no, status), rcr:rcr_id(rcr_no, status)",
      )
      .eq("barangay_id", barangay.id)
      .order("or_date", { ascending: false })
      .order("serial_no", { ascending: false })
      .limit(100),
  ]);

  const ors = (orRows ?? []) as unknown as OrRow[];
  const bookletList = (booklets ?? []) as Booklet[];

  return (
    <>
      <header className="row">
        <div>
          <h1>Official Receipts</h1>
          <p className="muted">{barangay.name} · Accountable Form No. 51, issued in strict serial order</p>
        </div>
      </header>
      <Flash ok={ok} error={error} />

      {canWrite && (
        <section className="card">
          <h2>Issue an Official Receipt</h2>
          {bookletList.length === 0 ? (
            <p className="error">
              No OR booklet is on hand. Record the booklet received from the City/Municipal Treasurer under
              accountable forms first.
            </p>
          ) : (
            <form action={issueOr} className="grid">
              <label>
                Booklet
                <select name="form_id" required defaultValue={bookletList[0].id}>
                  {bookletList.map((b) => (
                    <option key={b.id} value={b.id}>
                      {b.series ?? "Booklet"} · next No. {b.next_serial} (of {b.serial_from}–{b.serial_to})
                    </option>
                  ))}
                </select>
              </label>
              <label>
                Date
                <input name="or_date" type="date" required defaultValue={todayManila()} />
              </label>
              <label className="span2">
                Payor
                <input name="payor" required placeholder="Name of the person or entity paying" />
              </label>
              <label>
                Nature of collection
                <select name="collection_type_id" required>
                  {((types ?? []) as CollectionType[]).map((t) => (
                    <option key={t.id} value={t.id}>
                      {t.name}
                    </option>
                  ))}
                </select>
              </label>
              <label>
                Fund
                <select name="fund_id" required>
                  {((funds ?? []) as Fund[]).map((f) => (
                    <option key={f.id} value={f.id}>
                      {f.code} · {f.name}
                    </option>
                  ))}
                </select>
              </label>
              <label>
                Amount (₱)
                <input name="amount" type="number" step="0.01" min="0.01" required />
              </label>
              <label>
                Paid by
                <select name="payment_mode" defaultValue="cash">
                  <option value="cash">Cash</option>
                  <option value="check">Check</option>
                </select>
              </label>
              <label>
                Check: bank
                <input name="check_bank" placeholder="Only for checks" />
              </label>
              <label>
                Check: number
                <input name="check_no" placeholder="Only for checks" />
              </label>
              <label>
                Check: date
                <input name="check_date" type="date" />
              </label>
              <label className="span2">
                Particulars
                <input name="particulars" placeholder="Optional details written on the OR" />
              </label>
              <div className="span2">
                <button type="submit">Issue OR</button>
              </div>
            </form>
          )}
        </section>
      )}

      <section className="card">
        <h2>Receipts issued</h2>
        {ors.length === 0 ? (
          <p className="muted">No Official Receipts yet.</p>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>OR No.</th>
                  <th>Date</th>
                  <th>Payor</th>
                  <th>Nature</th>
                  <th>Fund</th>
                  <th className="num">Amount</th>
                  <th>Paid by</th>
                  <th>Reported on</th>
                  {canWrite && <th></th>}
                </tr>
              </thead>
              <tbody>
                {ors.map((o) => {
                  const frozen = (o.rcd && o.rcd.status !== "draft") || (o.rcr && o.rcr.status !== "draft");
                  return (
                    <tr key={o.id} className={o.status === "cancelled" ? "cancelled" : undefined}>
                      <td>{o.serial_no}</td>
                      <td>{formatDate(o.or_date)}</td>
                      <td>
                        {o.payor}
                        {o.status === "cancelled" && (
                          <span className="tag">CANCELLED{o.cancelled_reason ? `: ${o.cancelled_reason}` : ""}</span>
                        )}
                      </td>
                      <td>{o.nature}</td>
                      <td>{o.fund?.code}</td>
                      <td className="num">{o.status === "cancelled" ? "" : formatPeso(o.amount)}</td>
                      <td>{o.payment_mode === "check" ? `Check ${o.check_bank ?? ""} ${o.check_no ?? ""}`.trim() : "Cash"}</td>
                      <td>
                        {o.rcd ? `RCD ${o.rcd.rcd_no ?? "(draft)"}` : o.rcr ? `RCR ${o.rcr.rcr_no ?? "(draft)"}` : <span className="muted">not yet</span>}
                      </td>
                      {canWrite && (
                        <td>
                          {o.status === "issued" && !frozen && (
                            <form action={cancelOr} className="inline-form">
                              <input type="hidden" name="id" value={o.id} />
                              <input name="reason" placeholder="Reason" required size={12} />
                              <button type="submit" className="secondary small">
                                Cancel OR
                              </button>
                            </form>
                          )}
                        </td>
                      )}
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </>
  );
}
