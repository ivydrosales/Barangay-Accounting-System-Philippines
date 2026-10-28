import Link from "next/link";
import { notFound } from "next/navigation";
import { PrintButton } from "@/components/PrintButton";
import { requireBarangay } from "@/lib/context";
import { formatAmount, formatDate } from "@/lib/format";

type Check = {
  id: string;
  check_no: number;
  check_date: string;
  payee: string;
  amount: string;
  pbc_no: string;
  pbc_date: string;
  status: string;
  barangay_id: string;
  dv: { id: string; dv_no: string; dv_date: string; particulars: string; fund: { code: string } | null } | null;
  bank: { bank_name: string; branch: string | null; account_number: string; account_name: string } | null;
  barangay: { name: string; lgu: { name: string; province: string | null } | null } | null;
};

export default async function PbcPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { supabase } = await requireBarangay();

  const { data: row } = await supabase
    .from("bank_check")
    .select(
      "id, check_no, check_date, payee, amount, pbc_no, pbc_date, status, barangay_id, dv:dv_id(id, dv_no, dv_date, particulars, fund:fund_id(code)), bank:bank_account_id(bank_name, branch, account_number, account_name), barangay:barangay_id(name, lgu:lgu_id(name, province))",
    )
    .eq("id", id)
    .maybeSingle();
  if (!row) notFound();
  const check = row as unknown as Check;

  const { data: pb } = await supabase
    .from("official")
    .select("full_name")
    .eq("barangay_id", check.barangay_id)
    .eq("position", "Punong Barangay")
    .eq("is_active", true)
    .limit(1)
    .maybeSingle();

  const lgu = check.barangay?.lgu;

  return (
    <>
      <header className="row no-print">
        <div>
          <h1>PB Certification {check.pbc_no}</h1>
          <p className="muted">
            <Link href="/disbursements/checks">Check register</Link> · Check No. {check.check_no} ·{" "}
            {check.dv ? <Link href={`/disbursements/${check.dv.id}`}>DV {check.dv.dv_no}</Link> : null}
          </p>
        </div>
        <div className="actions">
          <PrintButton />
        </div>
      </header>

      <p className="muted no-print">
        Four copies (manual 5.2.1): original to the depository bank, released by the Treasurer; duplicate attached to the
        Transmittal Letter for the Accountant; the others for the Auditor and the Treasurer&apos;s file. The wording below follows
        the manual&apos;s description of the PBC under COA Circular No. 2012-005; confirm it against the circular&apos;s prescribed
        form with the Accountant before first use.
      </p>

      <article className="annex">
        <h2 className="annex-title">PUNONG BARANGAY CERTIFICATION</h2>
        <div className="annex-head">
          <div>
            <div>Barangay: <u>{check.barangay?.name}</u></div>
            <div>City/Municipality: <u>{lgu?.name}</u></div>
            <div>Province: <u>{lgu?.province ?? ""}</u></div>
          </div>
          <div>
            <div>PBC No.: <u>{check.pbc_no}</u></div>
            <div>Date: <u>{formatDate(check.pbc_date)}</u></div>
          </div>
        </div>

        <p>
          To: The Manager<br />
          {check.bank?.bank_name}
          {check.bank?.branch ? `, ${check.bank.branch}` : ""}
          <br />
          Account Name: {check.bank?.account_name} · Account No.: {check.bank?.account_number}
        </p>

        <p>
          I, <strong>{pb?.full_name ?? "________________________"}</strong>, Punong Barangay of Barangay {check.barangay?.name},{" "}
          {lgu?.name}
          {lgu?.province ? `, ${lgu.province}` : ""}, after having been duly sworn in accordance with law, hereby certify that the
          check listed below, drawn against the barangay&apos;s depository account named above, was issued in payment of a lawful
          obligation of the barangay covered by a Disbursement Voucher that carries the certifications of the Chairman of the
          Committee on Appropriations as to the existence of appropriation and of the Barangay Treasurer as to the availability
          of funds and completeness of supporting documents, and that I have examined and approved the claim as valid, proper
          and legal.
        </p>

        <table className="annex-table">
          <thead>
            <tr>
              <th>Check No.</th>
              <th>Check Date</th>
              <th>Payee</th>
              <th>DV No. / Date</th>
              <th>Fund</th>
              <th>Particulars</th>
              <th className="num">Amount</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td>{check.check_no}</td>
              <td>{formatDate(check.check_date)}</td>
              <td>{check.payee}</td>
              <td>
                {check.dv?.dv_no} / {formatDate(check.dv?.dv_date)}
              </td>
              <td>{check.dv?.fund?.code}</td>
              <td>{check.dv?.particulars}</td>
              <td className="num">{formatAmount(check.amount)}</td>
            </tr>
          </tbody>
        </table>

        <div className="sig-row">
          <div className="sig">
            <div className="sig-line">{pb?.full_name ?? ""}</div>
            <div className="sig-label">Punong Barangay</div>
          </div>
        </div>

        <div className="annex-box">
          <p>
            SUBSCRIBED AND SWORN to before me this ____ day of ______________, 20____ at ____________________, affiant exhibiting
            to me competent evidence of identity: ______________________________ issued on ______________ at ______________.
          </p>
          <div className="sig-row">
            <div className="sig">
              <div className="sig-line">&nbsp;</div>
              <div className="sig-label">Notary Public</div>
            </div>
            <div>
              <div>Doc. No. ______</div>
              <div>Page No. ______</div>
              <div>Book No. ______</div>
              <div>Series of 20____</div>
            </div>
          </div>
        </div>
      </article>
    </>
  );
}
