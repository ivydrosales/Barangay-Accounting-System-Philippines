import Link from "next/link";
import { Flash } from "@/components/Flash";
import { requireBarangay } from "@/lib/context";
import { formatDate, formatPeso } from "@/lib/format";
import { CHECK_STATUS } from "@/lib/labels";

type CheckRow = {
  id: string;
  check_no: number;
  check_date: string;
  payee: string;
  amount: string;
  pbc_no: string;
  status: string;
  released_on: string | null;
  dv: { id: string; dv_no: string; status: string } | null;
  bank: { bank_name: string; account_number: string } | null;
};

export default async function CheckRegisterPage({ searchParams }: { searchParams: Promise<{ ok?: string; error?: string }> }) {
  const { ok, error } = await searchParams;
  const { supabase, barangay } = await requireBarangay();

  const { data: rows } = await supabase
    .from("bank_check")
    .select("id, check_no, check_date, payee, amount, pbc_no, status, released_on, dv:dv_id(id, dv_no, status), bank:bank_account_id(bank_name, account_number)")
    .eq("barangay_id", barangay.id)
    .order("check_date", { ascending: false })
    .order("check_no", { ascending: false })
    .limit(200);
  const checks = (rows ?? []) as unknown as CheckRow[];

  return (
    <>
      <header className="row">
        <div>
          <h1>Check register</h1>
          <p className="muted">
            {barangay.name} · every check drawn on the depository account, with its Punong Barangay Certification (PBC).
            Checks are drawn from the <Link href="/disbursements">Disbursement Voucher</Link>; booklets are recorded under{" "}
            <Link href="/forms">Accountable forms</Link>.
          </p>
        </div>
      </header>
      <Flash ok={ok} error={error} />

      <section className="card">
        <h2>Checks</h2>
        {checks.length === 0 ? (
          <p className="muted">No checks yet.</p>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Check No.</th>
                  <th>Date</th>
                  <th>Payee</th>
                  <th className="num">Amount</th>
                  <th>DV No.</th>
                  <th>PBC No.</th>
                  <th>Status</th>
                  <th>Released</th>
                  <th>Bank</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {checks.map((c) => (
                  <tr key={c.id} className={["spoiled", "cancelled"].includes(c.status) ? "cancelled" : undefined}>
                    <td>{c.check_no}</td>
                    <td>{formatDate(c.check_date)}</td>
                    <td>{c.payee}</td>
                    <td className="num">{formatPeso(c.amount)}</td>
                    <td>{c.dv ? <Link href={`/disbursements/${c.dv.id}`}>{c.dv.dv_no}</Link> : ""}</td>
                    <td>{c.pbc_no}</td>
                    <td>{CHECK_STATUS[c.status] ?? c.status}</td>
                    <td>{formatDate(c.released_on)}</td>
                    <td>{c.bank ? `${c.bank.bank_name} ${c.bank.account_number}` : ""}</td>
                    <td>
                      <Link href={`/disbursements/checks/${c.id}`}>PB Certification</Link>
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
