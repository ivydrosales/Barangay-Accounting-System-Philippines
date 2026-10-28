import Link from "next/link";
import { Flash } from "@/components/Flash";
import { requireBarangay } from "@/lib/context";
import { formatDate, formatPeso, todayManila } from "@/lib/format";
import { addDeposit, deleteDeposit, prepareRcd } from "../actions";

type RcdRow = { id: string; rcd_no: string | null; rcd_date: string; status: string };
type Totals = { rcd_id: string; collections: string; deposits: string };
type BankAccount = { id: string; bank_name: string; branch: string | null; account_number: string };
type Fund = { id: string; code: string; name: string };
type DepositRow = {
  id: string;
  deposit_date: string;
  reference: string;
  amount: string;
  bank: { bank_name: string; account_number: string } | null;
  fund: { code: string } | null;
};

const STATUS: Record<string, string> = { draft: "Draft", certified: "Certified by Treasurer", posted: "Posted to JCT" };

export default async function RcdListPage({ searchParams }: { searchParams: Promise<{ ok?: string; error?: string }> }) {
  const { ok, error } = await searchParams;
  const { supabase, barangay, canWrite } = await requireBarangay();

  const [{ data: rows }, { data: banks }, { data: funds }, { data: pendingDeposits }] = await Promise.all([
    supabase.from("rcd").select("id, rcd_no, rcd_date, status").eq("barangay_id", barangay.id).order("rcd_date", { ascending: false }).limit(100),
    supabase.from("bank_account").select("id, bank_name, branch, account_number").eq("barangay_id", barangay.id).is("closed_on", null).order("bank_name"),
    supabase.from("fund").select("id, code, name").eq("barangay_id", barangay.id).eq("is_active", true).order("code"),
    supabase
      .from("deposit")
      .select("id, deposit_date, reference, amount, bank:bank_account_id(bank_name, account_number), fund:fund_id(code)")
      .eq("barangay_id", barangay.id)
      .is("rcd_id", null)
      .order("deposit_date", { ascending: false }),
  ]);
  const rcds = (rows ?? []) as RcdRow[];
  const { data: totalRows } = rcds.length
    ? await supabase.from("rcd_totals").select("rcd_id, collections, deposits").in("rcd_id", rcds.map((r) => r.id))
    : { data: [] as Totals[] };
  const totals = new Map(((totalRows ?? []) as Totals[]).map((t) => [t.rcd_id, t]));
  const deposits = (pendingDeposits ?? []) as unknown as DepositRow[];
  const bankList = (banks ?? []) as BankAccount[];

  return (
    <>
      <header className="row">
        <div>
          <h1>Report of Collections and Deposits</h1>
          <p className="muted">{barangay.name} · Annex 9 · the Treasurer&apos;s daily report, to the Accountant by the 5th</p>
        </div>
      </header>
      <Flash ok={ok} error={error} />

      {canWrite && (
        <div className="two-col">
          <section className="card">
            <h2>Record a deposit</h2>
            <p className="muted">From the validated deposit slip. Collections are deposited intact daily (4.1.12).</p>
            {bankList.length === 0 ? (
              <p className="error">No depository bank account is on record for this barangay.</p>
            ) : (
              <form action={addDeposit} className="grid">
                <input type="hidden" name="barangay_id" value={barangay.id} />
                <input type="hidden" name="lgu_id" value={barangay.lgu_id} />
                <label>
                  Bank account
                  <select name="bank_account_id" required>
                    {bankList.map((b) => (
                      <option key={b.id} value={b.id}>
                        {b.bank_name} {b.branch ? `(${b.branch})` : ""} · {b.account_number}
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
                  Date
                  <input name="deposit_date" type="date" required defaultValue={todayManila()} />
                </label>
                <label>
                  Deposit slip reference
                  <input name="reference" required placeholder="Validated DS number" />
                </label>
                <label>
                  Amount (₱)
                  <input name="amount" type="number" step="0.01" min="0.01" required />
                </label>
                <div>
                  <button type="submit">Record deposit</button>
                </div>
              </form>
            )}
          </section>

          <section className="card">
            <h2>Prepare the RCD</h2>
            <p className="muted">
              Gathers every unreported OR, every RCR you have acknowledged and every deposit dated on or before the report date.
            </p>
            <form action={prepareRcd} className="grid">
              <input type="hidden" name="barangay_id" value={barangay.id} />
              <label>
                Report date
                <input name="rcd_date" type="date" required defaultValue={todayManila()} />
              </label>
              <div>
                <button type="submit">Prepare draft RCD</button>
              </div>
            </form>
          </section>
        </div>
      )}

      {deposits.length > 0 && (
        <section className="card">
          <h2>Deposits not yet on an RCD</h2>
          <table>
            <thead>
              <tr><th>Date</th><th>Bank</th><th>Fund</th><th>Reference</th><th className="num">Amount</th>{canWrite && <th></th>}</tr>
            </thead>
            <tbody>
              {deposits.map((d) => (
                <tr key={d.id}>
                  <td>{formatDate(d.deposit_date)}</td>
                  <td>{d.bank?.bank_name} {d.bank?.account_number}</td>
                  <td>{d.fund?.code}</td>
                  <td>{d.reference}</td>
                  <td className="num">{formatPeso(d.amount)}</td>
                  {canWrite && (
                    <td>
                      <form action={deleteDeposit}>
                        <input type="hidden" name="id" value={d.id} />
                        <button type="submit" className="secondary small">Remove</button>
                      </form>
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        </section>
      )}

      <section className="card">
        <h2>Reports</h2>
        {rcds.length === 0 ? (
          <p className="muted">No RCDs yet.</p>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>RCD No.</th>
                  <th>Date</th>
                  <th className="num">Collections</th>
                  <th className="num">Deposits</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                {rcds.map((r) => (
                  <tr key={r.id}>
                    <td><Link href={`/collections/rcd/${r.id}`}>{r.rcd_no ?? "(draft)"}</Link></td>
                    <td>{formatDate(r.rcd_date)}</td>
                    <td className="num">{formatPeso(totals.get(r.id)?.collections ?? 0)}</td>
                    <td className="num">{formatPeso(totals.get(r.id)?.deposits ?? 0)}</td>
                    <td>{STATUS[r.status] ?? r.status}</td>
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
