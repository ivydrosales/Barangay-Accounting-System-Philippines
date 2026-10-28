import { PrintButton } from "@/components/PrintButton";
import { requireBarangay } from "@/lib/context";
import { MONTHS, formatAmount, formatDate, todayManila } from "@/lib/format";

type Row = {
  seq: number;
  entry_date: string;
  particulars: string;
  reference: string | null;
  clt_collection: string | null; clt_deposit: string | null; clt_balance: string | null;
  cib_deposit: string | null; cib_check: string | null; cib_balance: string | null;
  ca_receipt: string | null; ca_disbursement: string | null; ca_balance: string | null;
  pc_receipt: string | null; pc_payment: string | null; pc_balance: string | null;
};

const SUM_COLS = ["clt_collection", "clt_deposit", "cib_deposit", "cib_check", "ca_receipt", "ca_disbursement", "pc_receipt", "pc_payment"] as const;

export default async function CashbookPage({ searchParams }: { searchParams: Promise<{ year?: string; month?: string }> }) {
  const sp = await searchParams;
  const today = todayManila();
  const year = Number(sp.year ?? today.slice(0, 4));
  const month = Number(sp.month ?? today.slice(5, 7));
  const { supabase, barangay } = await requireBarangay();

  const [{ data: rowData }, { data: treasurer }] = await Promise.all([
    supabase.rpc("cashbook", { p_barangay: barangay.id, p_year: year, p_month: month }),
    supabase.from("official").select("full_name").eq("barangay_id", barangay.id).eq("position", "Barangay Treasurer").eq("is_active", true).limit(1).maybeSingle(),
  ]);
  const rows = (rowData ?? []) as Row[];
  const beginning = rows.find((r) => r.seq === 0);
  const lines = rows.filter((r) => r.seq > 0);
  const last = lines[lines.length - 1] ?? beginning;
  const totals = Object.fromEntries(SUM_COLS.map((c) => [c, lines.reduce((acc, r) => acc + Number(r[c] ?? 0), 0)])) as Record<(typeof SUM_COLS)[number], number>;
  const monthEnd = new Date(Date.UTC(year, month, 0)).toISOString().slice(0, 10);

  const years = [year - 1, year, year + 1];

  return (
    <>
      <style>{`@page { size: A4 landscape; margin: 10mm; }`}</style>
      <header className="row no-print">
        <div>
          <h1>Cashbook</h1>
          <p className="muted">{barangay.name} · Annex 8 · updated daily from the RCD, certified monthly by the Treasurer</p>
        </div>
        <div className="actions">
          <form method="get" className="inline-form">
            <select name="month" defaultValue={month} aria-label="Month">
              {MONTHS.map((m, i) => (
                <option key={m} value={i + 1}>{m}</option>
              ))}
            </select>
            <select name="year" defaultValue={year} aria-label="Year">
              {years.map((y) => (
                <option key={y} value={y}>{y}</option>
              ))}
            </select>
            <button type="submit" className="secondary small">Show</button>
          </form>
          <PrintButton />
        </div>
      </header>

      <article className="annex landscape">
        <div className="annex-tag">Annex 8</div>
        <h2 className="annex-title">CASHBOOK</h2>
        <div className="annex-head">
          <div>
            <div>Barangay: <u>{barangay.name}</u></div>
            <div>Barangay Treasurer: <u>{treasurer?.full_name ?? "—"}</u></div>
            <div>Calendar Year: <u>{MONTHS[month - 1]} {year}</u></div>
          </div>
        </div>

        <table className="annex-table small cashbook">
          <thead>
            <tr>
              <th rowSpan={2}>Date</th>
              <th rowSpan={2}>Particulars</th>
              <th rowSpan={2}>Reference</th>
              <th colSpan={3}>Cash in Local Treasury</th>
              <th colSpan={3}>Cash in Bank</th>
              <th colSpan={3}>Cash Advance</th>
              <th colSpan={3}>Petty Cash</th>
            </tr>
            <tr>
              <th>Collection</th><th>Deposit</th><th>Balance</th>
              <th>Deposit</th><th>Check Issued</th><th>Balance</th>
              <th>Receipt</th><th>Disbursements</th><th>Balance</th>
              <th>Receipt/ Replenishment</th><th>Payments</th><th>Balance</th>
            </tr>
          </thead>
          <tbody>
            {beginning && (
              <tr>
                <td>{formatDate(beginning.entry_date)}</td>
                <td>Bal. Beginning</td>
                <td></td>
                <td></td><td></td><td className="num">{formatAmount(beginning.clt_balance) || "0.00"}</td>
                <td></td><td></td><td className="num">{formatAmount(beginning.cib_balance) || "0.00"}</td>
                <td></td><td></td><td className="num">{formatAmount(beginning.ca_balance) || "0.00"}</td>
                <td></td><td></td><td className="num">{formatAmount(beginning.pc_balance) || "0.00"}</td>
              </tr>
            )}
            {lines.map((r) => (
              <tr key={r.seq}>
                <td>{formatDate(r.entry_date)}</td>
                <td>{r.particulars}</td>
                <td>{r.reference}</td>
                <td className="num">{formatAmount(r.clt_collection)}</td><td className="num">{formatAmount(r.clt_deposit)}</td><td className="num">{formatAmount(r.clt_balance) || "0.00"}</td>
                <td className="num">{formatAmount(r.cib_deposit)}</td><td className="num">{formatAmount(r.cib_check)}</td><td className="num">{formatAmount(r.cib_balance) || "0.00"}</td>
                <td className="num">{formatAmount(r.ca_receipt)}</td><td className="num">{formatAmount(r.ca_disbursement)}</td><td className="num">{formatAmount(r.ca_balance) || "0.00"}</td>
                <td className="num">{formatAmount(r.pc_receipt)}</td><td className="num">{formatAmount(r.pc_payment)}</td><td className="num">{formatAmount(r.pc_balance) || "0.00"}</td>
              </tr>
            ))}
            <tr className="total">
              <td>{formatDate(monthEnd)}</td>
              <td>Totals</td>
              <td></td>
              <td className="num">{formatAmount(totals.clt_collection)}</td><td className="num">{formatAmount(totals.clt_deposit)}</td><td></td>
              <td className="num">{formatAmount(totals.cib_deposit)}</td><td className="num">{formatAmount(totals.cib_check)}</td><td></td>
              <td className="num">{formatAmount(totals.ca_receipt)}</td><td className="num">{formatAmount(totals.ca_disbursement)}</td><td></td>
              <td className="num">{formatAmount(totals.pc_receipt)}</td><td className="num">{formatAmount(totals.pc_payment)}</td><td></td>
            </tr>
            <tr className="total">
              <td>{formatDate(monthEnd)}</td>
              <td>Bal. Ending</td>
              <td></td>
              <td></td><td></td><td className="num">{formatAmount(last?.clt_balance) || "0.00"}</td>
              <td></td><td></td><td className="num">{formatAmount(last?.cib_balance) || "0.00"}</td>
              <td></td><td></td><td className="num">{formatAmount(last?.ca_balance) || "0.00"}</td>
              <td></td><td></td><td className="num">{formatAmount(last?.pc_balance) || "0.00"}</td>
            </tr>
          </tbody>
        </table>

        <div className="annex-box">
          <h3 className="annex-section">CERTIFICATION:</h3>
          <p>
            I hereby certify that the foregoing is a correct and complete record of all my collections, deposits/remittances and balances of my accounts in the Cash – In Local Treasury, Cash in Bank, Cash Advances, and Petty Cash as of {formatDate(monthEnd)}.
          </p>
          <div className="sig-row">
            <div className="sig">
              <div className="sig-line">{treasurer?.full_name ?? ""}</div>
              <div className="sig-label">Name and Signature</div>
            </div>
            <div className="sig">
              <div className="sig-line">&nbsp;</div>
              <div className="sig-label">Date</div>
            </div>
          </div>
        </div>
      </article>
    </>
  );
}
