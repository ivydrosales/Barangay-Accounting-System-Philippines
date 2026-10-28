import Link from "next/link";
import { Flash } from "@/components/Flash";
import { requireBarangay } from "@/lib/context";
import { formatDate, formatPeso, todayManila } from "@/lib/format";
import { DV_STATUS } from "@/lib/labels";
import { createDv } from "./actions";

type Fund = { id: string; code: string; name: string };
type Supplier = { id: string; name: string; tin: string | null; address: string | null };
type Employee = { id: string; full_name: string; position: string | null };
type Account = { code: string; title: string; class: string };
type DvRow = {
  id: string;
  dv_no: string;
  dv_date: string;
  payee: string;
  particulars: string;
  amount: string;
  status: string;
  fund: { code: string } | null;
};
type Totals = { dv_id: string; net_amount: string };
type CheckRow = { dv_id: string; check_no: number };

const CHARGE_ROWS = 4;
const DEDUCTION_ROWS = 2;

export default async function DisbursementsPage({ searchParams }: { searchParams: Promise<{ ok?: string; error?: string }> }) {
  const { ok, error } = await searchParams;
  const { supabase, barangay, canWrite } = await requireBarangay();

  const [{ data: funds }, { data: suppliers }, { data: employees }, { data: accounts }, { data: dvRows }] = await Promise.all([
    supabase.from("fund").select("id, code, name").eq("barangay_id", barangay.id).eq("is_active", true).order("code"),
    supabase.from("supplier").select("id, name, tin, address").eq("lgu_id", barangay.lgu_id).eq("is_active", true).order("name"),
    supabase.from("employee").select("id, full_name, position").eq("barangay_id", barangay.id).eq("is_active", true).order("full_name"),
    supabase.from("account").select("code, title, class").eq("is_active", true).in("class", ["Expense", "Asset", "Liability"]).order("code"),
    supabase
      .from("disbursement_voucher")
      .select("id, dv_no, dv_date, payee, particulars, amount, status, fund:fund_id(code)")
      .eq("barangay_id", barangay.id)
      .order("dv_no", { ascending: false })
      .limit(100),
  ]);
  const dvs = (dvRows ?? []) as unknown as DvRow[];
  const ids = dvs.map((d) => d.id);
  const [{ data: totalRows }, { data: checkRows }] = ids.length
    ? await Promise.all([
        supabase.from("dv_totals").select("dv_id, net_amount").in("dv_id", ids),
        supabase.from("bank_check").select("dv_id, check_no").in("dv_id", ids),
      ])
    : [{ data: [] as Totals[] }, { data: [] as CheckRow[] }];
  const net = new Map(((totalRows ?? []) as Totals[]).map((t) => [t.dv_id, t.net_amount]));
  const checks = new Map(((checkRows ?? []) as CheckRow[]).map((c) => [c.dv_id, c.check_no]));
  const accountList = (accounts ?? []) as Account[];
  const liabilities = accountList.filter((a) => a.class === "Liability");

  return (
    <>
      <header className="row">
        <div>
          <h1>Disbursement Vouchers</h1>
          <p className="muted">
            {barangay.name} · Annex 12 · nothing is paid without Boxes A (CCA), B (Treasurer) and C (Punong Barangay) ·{" "}
            <Link href="/disbursements/checks">Check register</Link> · <Link href="/disbursements/transmittal">Transmittal Letters</Link>
          </p>
        </div>
      </header>
      <Flash ok={ok} error={error} />

      {canWrite && (
        <section className="card">
          <h2>Prepare a Disbursement Voucher</h2>
          <p className="muted">
            The amount of the claim is the total of the charges. Deductions (withholding taxes and other amounts due to others)
            are taken out of the check. The DV gets its number now; a voucher that is not pursued is cancelled, not deleted.
          </p>
          <form action={createDv} className="grid">
            <input type="hidden" name="barangay_id" value={barangay.id} />
            <label>
              Date
              <input name="dv_date" type="date" required defaultValue={todayManila()} />
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
            <label className="span2">
              Payee
              <input name="payee" required placeholder="Name of the person or entity to be paid" />
            </label>
            <label>
              Payee TIN
              <input name="payee_tin" placeholder="Optional" />
            </label>
            <label>
              Payee address
              <input name="payee_address" placeholder="Optional" />
            </label>
            <label>
              Supplier on file (for the creditor&apos;s subsidiary ledger)
              <select name="supplier_id" defaultValue="">
                <option value="">None</option>
                {((suppliers ?? []) as Supplier[]).map((s) => (
                  <option key={s.id} value={s.id}>
                    {s.name}
                  </option>
                ))}
              </select>
            </label>
            <label>
              Employee on file
              <select name="employee_id" defaultValue="">
                <option value="">None</option>
                {((employees ?? []) as Employee[]).map((e) => (
                  <option key={e.id} value={e.id}>
                    {e.full_name}
                    {e.position ? ` · ${e.position}` : ""}
                  </option>
                ))}
              </select>
            </label>
            <label className="span2">
              Particulars
              <textarea name="particulars" required rows={3} placeholder="Brief description of the expense or obligation being paid" />
            </label>

            <div className="span2">
              <h3>Charges (debits)</h3>
              <p className="muted">Pick the expense, asset or payable account. Type a code such as 5-02-03-010 or the account title.</p>
              <div className="table-wrap">
                <table>
                  <thead>
                    <tr>
                      <th>Account</th>
                      <th className="num">Amount (₱)</th>
                      <th>Particulars</th>
                    </tr>
                  </thead>
                  <tbody>
                    {Array.from({ length: CHARGE_ROWS }, (_, i) => (
                      <tr key={i}>
                        <td>
                          <input name="charge_account" list="charge-accounts" placeholder="Code or title" required={i === 0} />
                        </td>
                        <td className="num">
                          <input name="charge_amount" type="number" step="0.01" min="0" required={i === 0} />
                        </td>
                        <td>
                          <input name="charge_particulars" placeholder="Optional" />
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>

            <div className="span2">
              <h3>Deductions (credits)</h3>
              <p className="muted">Amounts withheld from the payee, for example Due to BIR (2-02-01-010). Leave blank if none.</p>
              <div className="table-wrap">
                <table>
                  <thead>
                    <tr>
                      <th>Account</th>
                      <th className="num">Amount (₱)</th>
                      <th>Particulars</th>
                    </tr>
                  </thead>
                  <tbody>
                    {Array.from({ length: DEDUCTION_ROWS }, (_, i) => (
                      <tr key={i}>
                        <td>
                          <input name="deduction_account" list="deduction-accounts" placeholder="Code or title" />
                        </td>
                        <td className="num">
                          <input name="deduction_amount" type="number" step="0.01" min="0" />
                        </td>
                        <td>
                          <input name="deduction_particulars" placeholder="Optional" />
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>

            <datalist id="charge-accounts">
              {accountList.map((a) => (
                <option key={a.code} value={a.code}>
                  {a.title}
                </option>
              ))}
            </datalist>
            <datalist id="deduction-accounts">
              {liabilities.map((a) => (
                <option key={a.code} value={a.code}>
                  {a.title}
                </option>
              ))}
            </datalist>

            <div className="span2">
              <button type="submit">Prepare DV</button>
            </div>
          </form>
        </section>
      )}

      <section className="card">
        <h2>Vouchers</h2>
        {dvs.length === 0 ? (
          <p className="muted">No Disbursement Vouchers yet.</p>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>DV No.</th>
                  <th>Date</th>
                  <th>Payee</th>
                  <th>Particulars</th>
                  <th>Fund</th>
                  <th className="num">Amount</th>
                  <th className="num">Net of deductions</th>
                  <th>Check</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                {dvs.map((d) => (
                  <tr key={d.id} className={d.status === "cancelled" ? "cancelled" : undefined}>
                    <td>
                      <Link href={`/disbursements/${d.id}`}>{d.dv_no}</Link>
                    </td>
                    <td>{formatDate(d.dv_date)}</td>
                    <td>{d.payee}</td>
                    <td>{d.particulars.length > 60 ? d.particulars.slice(0, 60) + "…" : d.particulars}</td>
                    <td>{d.fund?.code}</td>
                    <td className="num">{formatPeso(d.amount)}</td>
                    <td className="num">{formatPeso(net.get(d.id) ?? d.amount)}</td>
                    <td>{checks.get(d.id) ?? ""}</td>
                    <td>{DV_STATUS[d.status] ?? d.status}</td>
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
