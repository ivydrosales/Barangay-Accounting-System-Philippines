import Link from "next/link";
import { notFound } from "next/navigation";
import { Flash } from "@/components/Flash";
import { PrintButton } from "@/components/PrintButton";
import { requireBarangay } from "@/lib/context";
import { formatAmount, formatDate, formatPeso, todayManila } from "@/lib/format";
import { DV_STATUS } from "@/lib/labels";
import { approveDv, cancelDv, certifyBoxA, certifyBoxB, issueCheck, postDv, releaseCheck } from "../actions";

type Dv = {
  id: string;
  dv_no: string;
  dv_date: string;
  payee: string;
  payee_tin: string | null;
  payee_address: string | null;
  particulars: string;
  amount: string;
  status: string;
  cancelled_reason: string | null;
  received_by: string | null;
  received_on: string | null;
  payee_or_no: string | null;
  box_a_at: string | null;
  box_b_at: string | null;
  box_c_at: string | null;
  barangay_id: string;
  fund: { code: string; name: string } | null;
  barangay: { name: string; lgu: { name: string; lgu_type: string; province: string | null } | null } | null;
  box_a: { full_name: string } | null;
  box_b: { full_name: string } | null;
  box_c: { full_name: string } | null;
  transmittal: { id: string; tl_no: string | null; status: string } | null;
};
type Line = { line_no: number; kind: string; account_code: string; amount: string; particulars: string | null; account: { title: string } | null };
type Check = {
  id: string;
  check_no: number;
  check_date: string;
  amount: string;
  pbc_no: string;
  pbc_date: string;
  status: string;
  released_on: string | null;
  bank: { bank_name: string; branch: string | null; account_number: string } | null;
};
type Booklet = { id: string; series: string | null; serial_from: number; serial_to: number; next_serial: number };
type Official = { position: string; full_name: string };
type Depository = { gl_account_code: string; account: { title: string } | null };
type EntryLine = { line_no: number; account_code: string; debit: string; credit: string; account: { title: string } | null; entry: { entry_no: string; status: string } | null };

const BOX_POSITIONS = {
  a: "Chairman, Committee on Appropriations",
  b: "Barangay Treasurer",
  c: "Punong Barangay",
};

export default async function DvPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ ok?: string; error?: string }>;
}) {
  const { id } = await params;
  const { ok, error } = await searchParams;
  const { supabase, canWrite, isLguStaff, roles } = await requireBarangay();

  const { data: dvRow } = await supabase
    .from("disbursement_voucher")
    .select(
      "id, dv_no, dv_date, payee, payee_tin, payee_address, particulars, amount, status, cancelled_reason, received_by, received_on, payee_or_no, box_a_at, box_b_at, box_c_at, barangay_id, fund:fund_id(code, name), barangay:barangay_id(name, lgu:lgu_id(name, lgu_type, province)), box_a:box_a_official_id(full_name), box_b:box_b_official_id(full_name), box_c:box_c_official_id(full_name), transmittal:transmittal_id(id, tl_no, status)",
    )
    .eq("id", id)
    .maybeSingle();
  if (!dvRow) notFound();
  const dv = dvRow as unknown as Dv;

  const [{ data: lineRows }, { data: checkRow }, { data: bookletRows }, { data: officialRows }, { data: entryRows }, { data: depositoryRow }] = await Promise.all([
    supabase.from("dv_line").select("line_no, kind, account_code, amount, particulars, account:account_code(title)").eq("dv_id", id).order("line_no"),
    supabase
      .from("bank_check")
      .select("id, check_no, check_date, amount, pbc_no, pbc_date, status, released_on, bank:bank_account_id(bank_name, branch, account_number)")
      .eq("dv_id", id)
      .maybeSingle(),
    supabase
      .from("accountable_form")
      .select("id, series, serial_from, serial_to, next_serial")
      .eq("barangay_id", dv.barangay_id)
      .eq("form_type", "check")
      .in("status", ["on_hand", "in_use"])
      .order("serial_from"),
    supabase
      .from("official")
      .select("position, full_name")
      .eq("barangay_id", dv.barangay_id)
      .eq("is_active", true)
      .in("position", Object.values(BOX_POSITIONS)),
    supabase
      .from("journal_line")
      .select("line_no, account_code, debit, credit, account:account_code(title), entry:entry_id!inner(entry_no, status, source_id)")
      .eq("entry.source_id", id)
      .neq("entry.status", "reversed")
      .order("line_no"),
    supabase
      .from("bank_account")
      .select("gl_account_code, account:gl_account_code(title)")
      .eq("barangay_id", dv.barangay_id)
      .eq("is_depository", true)
      .is("closed_on", null)
      .limit(1)
      .maybeSingle(),
  ]);
  const lines = (lineRows ?? []) as unknown as Line[];
  const check = (checkRow ?? null) as unknown as Check | null;
  const booklets = (bookletRows ?? []) as Booklet[];
  const officials = (officialRows ?? []) as Official[];
  const entryLines = (entryRows ?? []) as unknown as EntryLine[];
  const depository = (depositoryRow ?? null) as unknown as Depository | null;
  const holder = (position: string) => officials.find((o) => o.position === position)?.full_name ?? "";

  const charges = lines.filter((l) => l.kind === "charge");
  const deductions = lines.filter((l) => l.kind === "deduction");
  const deductionTotal = deductions.reduce((acc, l) => acc + Number(l.amount), 0);
  const netAmount = Number(dv.amount) - deductionTotal;
  const lgu = dv.barangay?.lgu;
  const cancellable = ["draft", "certified_a", "certified_b", "approved"].includes(dv.status);
  const posted = entryLines.length > 0;

  // Box E on paper: the posted entry when there is one, else the lines planned on the voucher.
  const boxE = posted
    ? entryLines.map((l) => ({ title: l.account?.title ?? "", code: l.account_code, debit: l.debit, credit: l.credit }))
    : [
        ...charges.map((l) => ({ title: l.account?.title ?? "", code: l.account_code, debit: l.amount, credit: "0" })),
        ...deductions.map((l) => ({ title: l.account?.title ?? "", code: l.account_code, debit: "0", credit: l.amount })),
        {
          title: depository?.account?.title ?? "Cash in Bank – Local Currency, Current Account",
          code: depository?.gl_account_code ?? "1-01-02-010",
          debit: "0",
          credit: String(netAmount),
        },
      ];

  return (
    <>
      <header className="row no-print">
        <div>
          <h1>DV {dv.dv_no}</h1>
          <p className="muted">
            <Link href="/disbursements">All DVs</Link> · {DV_STATUS[dv.status] ?? dv.status}
            {dv.transmittal ? (
              <>
                {" "}
                · on <Link href={`/disbursements/transmittal/${dv.transmittal.id}`}>TL {dv.transmittal.tl_no ?? "(draft)"}</Link>
              </>
            ) : null}
          </p>
        </div>
        <div className="actions">
          <PrintButton />
          {check && (
            <Link href={`/disbursements/checks/${check.id}`} className="button secondary">
              PB Certification
            </Link>
          )}
        </div>
      </header>
      <Flash ok={ok} error={error} />

      {canWrite && dv.status !== "cancelled" && (
        <section className="card">
          <h2>Next step</h2>
          {dv.status === "draft" &&
            (roles.has("cca") ? (
              <form action={certifyBoxA} className="inline-form">
                <input type="hidden" name="id" value={dv.id} />
                <button type="submit">Certify Box A: appropriation exists (CCA)</button>
              </form>
            ) : (
              <p className="muted">Waiting for the Chairman of the Committee on Appropriations to certify Box A.</p>
            ))}
          {dv.status === "certified_a" &&
            (roles.has("barangay_treasurer") ? (
              <form action={certifyBoxB} className="inline-form">
                <input type="hidden" name="id" value={dv.id} />
                <button type="submit">Certify Box B: funds available, documents complete (Treasurer)</button>
              </form>
            ) : (
              <p className="muted">Waiting for the Barangay Treasurer to certify Box B.</p>
            ))}
          {dv.status === "certified_b" &&
            (roles.has("punong_barangay") ? (
              <form action={approveDv} className="inline-form">
                <input type="hidden" name="id" value={dv.id} />
                <button type="submit">Approve Box C (Punong Barangay)</button>
              </form>
            ) : (
              <p className="muted">Waiting for the Punong Barangay to approve Box C.</p>
            ))}
          {dv.status === "approved" &&
            (roles.has("barangay_treasurer") ? (
              booklets.length === 0 ? (
                <p className="error">
                  No check booklet is on hand. Record the booklet under <Link href="/forms">Accountable forms</Link> first.
                </p>
              ) : (
                <form action={issueCheck} className="grid">
                  <input type="hidden" name="id" value={dv.id} />
                  <label>
                    Check booklet
                    <select name="booklet_id" required defaultValue={booklets[0].id}>
                      {booklets.map((b) => (
                        <option key={b.id} value={b.id}>
                          {b.series ?? "Booklet"} · next No. {b.next_serial} (of {b.serial_from}–{b.serial_to})
                        </option>
                      ))}
                    </select>
                  </label>
                  <label>
                    Check date
                    <input name="check_date" type="date" required defaultValue={todayManila()} />
                  </label>
                  <div className="span2">
                    <button type="submit">Draw check for {formatPeso(netAmount)} (Treasurer)</button>
                    <span className="muted"> The Punong Barangay countersigns the check and signs the PB Certification.</span>
                  </div>
                </form>
              )
            ) : (
              <p className="muted">Waiting for the Barangay Treasurer to draw the check.</p>
            ))}
          {dv.status === "check_issued" && (
            <form action={releaseCheck} className="grid">
              <input type="hidden" name="id" value={dv.id} />
              <p className="span2 muted">
                Box D: the payee or their representative signs on receiving Check No. {check?.check_no}.
              </p>
              <label>
                Received by
                <input name="received_by" required defaultValue={dv.payee} />
              </label>
              <label>
                Date received
                <input name="received_on" type="date" required defaultValue={todayManila()} />
              </label>
              <label className="span2">
                Payee&apos;s OR or other receipt No. and date
                <input name="payee_or_no" placeholder="Optional" />
              </label>
              <div className="span2">
                <button type="submit">Record receipt of the check</button>
              </div>
            </form>
          )}
          {dv.status === "paid" &&
            (posted ? (
              <p className="muted">Posted to the JCT as entry {entryLines[0]?.entry?.entry_no}.</p>
            ) : isLguStaff ? (
              <form action={postDv} className="inline-form">
                <input type="hidden" name="id" value={dv.id} />
                <button type="submit">Post to JCT (Accountant)</button>
              </form>
            ) : (
              <p className="muted">Paid. The Accountant&apos;s office posts it to the JCT when the Transmittal Letter arrives.</p>
            ))}
          {cancellable && (
            <form action={cancelDv} className="inline-form" style={{ marginTop: 12 }}>
              <input type="hidden" name="id" value={dv.id} />
              <input name="reason" placeholder="Reason for cancelling" required size={32} />
              <button type="submit" className="secondary small">
                Cancel DV
              </button>
            </form>
          )}
        </section>
      )}

      <article className="annex">
        <div className="annex-tag">Annex 12</div>
        <h2 className="annex-title">DISBURSEMENT VOUCHER</h2>
        <div className="annex-head">
          <div>
            <div>Barangay: <u>{dv.barangay?.name}</u></div>
            <div>City/Municipality: <u>{lgu?.name}</u></div>
            <div>Province: <u>{lgu?.province ?? ""}</u></div>
          </div>
          <div>
            <div>DV No.: <u>{dv.dv_no}</u></div>
            <div>Date: <u>{formatDate(dv.dv_date)}</u></div>
            <div>Fund: <u>{dv.fund?.code}</u></div>
          </div>
        </div>

        <table className="annex-table">
          <tbody>
            <tr>
              <td style={{ width: "14%" }}>Payee</td>
              <td colSpan={2}>{dv.payee}</td>
              <td style={{ width: "10%" }}>TIN</td>
              <td style={{ width: "22%" }}>{dv.payee_tin ?? ""}</td>
            </tr>
            <tr>
              <td>Address</td>
              <td colSpan={4}>{dv.payee_address ?? ""}</td>
            </tr>
            <tr>
              <th colSpan={4}>Particulars</th>
              <th className="num">Amount</th>
            </tr>
            <tr>
              <td colSpan={4} style={{ verticalAlign: "top", minHeight: 80, whiteSpace: "pre-wrap" }}>
                {dv.particulars}
                {dv.status === "cancelled" && (
                  <div style={{ marginTop: 8, fontWeight: 700 }}>CANCELLED{dv.cancelled_reason ? `: ${dv.cancelled_reason}` : ""}</div>
                )}
              </td>
              <td className="num" style={{ verticalAlign: "top" }}>{formatAmount(dv.amount)}</td>
            </tr>
            {deductions.map((l) => (
              <tr key={l.line_no}>
                <td colSpan={4} className="indent">Less: {l.account?.title}{l.particulars ? ` (${l.particulars})` : ""}</td>
                <td className="num">({formatAmount(l.amount)})</td>
              </tr>
            ))}
            {deductions.length > 0 && (
              <tr className="total">
                <td colSpan={4}>Net amount of check</td>
                <td className="num">{formatAmount(netAmount)}</td>
              </tr>
            )}
          </tbody>
        </table>

        <div className="annex-two">
          <div className="annex-box">
            <strong>A</strong> Certified: Existence of available appropriation for the obligation.
            <div className="sig">
              <div className="sig-line">{dv.box_a?.full_name || holder(BOX_POSITIONS.a)}</div>
              <div className="sig-label">Chairman, Committee on Appropriations</div>
              <div className="sig-date">Date: {dv.box_a_at ? formatDate(dv.box_a_at.slice(0, 10)) : "____________"}</div>
            </div>
          </div>
          <div className="annex-box">
            <strong>B</strong> Certified: Funds available for the purpose; supporting documents complete and proper.
            <div className="sig">
              <div className="sig-line">{dv.box_b?.full_name || holder(BOX_POSITIONS.b)}</div>
              <div className="sig-label">Barangay Treasurer</div>
              <div className="sig-date">Date: {dv.box_b_at ? formatDate(dv.box_b_at.slice(0, 10)) : "____________"}</div>
            </div>
          </div>
        </div>
        <div className="annex-two">
          <div className="annex-box">
            <strong>C</strong> Certified: Validity, propriety and legality of the claim. Approved for payment.
            <div className="sig">
              <div className="sig-line">{dv.box_c?.full_name || holder(BOX_POSITIONS.c)}</div>
              <div className="sig-label">Punong Barangay</div>
              <div className="sig-date">Date: {dv.box_c_at ? formatDate(dv.box_c_at.slice(0, 10)) : "____________"}</div>
            </div>
          </div>
          <div className="annex-box">
            <strong>D</strong> Received payment.
            <table className="annex-table small" style={{ marginTop: 6 }}>
              <tbody>
                <tr><td>Check No.</td><td>{check?.check_no ?? ""}</td><td>Date</td><td>{formatDate(check?.check_date)}</td></tr>
                <tr><td>Bank/Branch</td><td colSpan={3}>{check ? `${check.bank?.bank_name ?? ""}${check.bank?.branch ? ` / ${check.bank.branch}` : ""}` : ""}</td></tr>
                <tr><td>OR/Doc. No.</td><td colSpan={3}>{dv.payee_or_no ?? ""}</td></tr>
              </tbody>
            </table>
            <div className="sig">
              <div className="sig-line">{dv.received_by ?? ""}</div>
              <div className="sig-label">Signature over printed name of payee/representative</div>
              <div className="sig-date">Date: {dv.received_on ? formatDate(dv.received_on) : "____________"}</div>
            </div>
          </div>
        </div>

        <div className="annex-box">
          <strong>E</strong> Accounting entries
          <table className="annex-table" style={{ marginTop: 6 }}>
            <thead>
              <tr><th>Account Title</th><th>Account Code</th><th className="num">Debit</th><th className="num">Credit</th></tr>
            </thead>
            <tbody>
              {boxE.map((l, i) => (
                <tr key={i}>
                  <td className={Number(l.credit) > 0 ? "indent" : undefined}>{l.title}</td>
                  <td>{l.code}</td>
                  <td className="num">{formatAmount(l.debit)}</td>
                  <td className="num">{formatAmount(l.credit)}</td>
                </tr>
              ))}
            </tbody>
          </table>
          <div className="sig-row">
            <div className="sig">
              <div className="sig-line">&nbsp;</div>
              <div className="sig-label">Prepared by: Barangay Bookkeeper · Date</div>
            </div>
            <div className="sig">
              <div className="sig-line">{posted ? `JCT ${entryLines[0]?.entry?.entry_no}` : ""}</div>
              <div className="sig-label">Approved by: City/Municipal Accountant · Date</div>
            </div>
          </div>
        </div>
      </article>

      <p className="muted no-print">
        Claim {formatPeso(dv.amount)} · Deductions {formatPeso(deductionTotal)} · Check {formatPeso(netAmount)}
        {check ? ` · Check No. ${check.check_no} dated ${formatDate(check.check_date)}, PBC ${check.pbc_no}` : ""}
      </p>
    </>
  );
}
