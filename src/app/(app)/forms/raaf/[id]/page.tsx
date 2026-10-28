import Link from "next/link";
import { notFound } from "next/navigation";
import { Flash } from "@/components/Flash";
import { PrintButton } from "@/components/PrintButton";
import { requireBarangay } from "@/lib/context";
import { MONTHS, formatDate } from "@/lib/format";
import { certifyRaaf, deleteRaaf } from "../../actions";

type Raaf = {
  id: string;
  raaf_no: string | null;
  period_year: number;
  period_month: number;
  status: string;
  certified_at: string | null;
  barangay_id: string;
  treasurer: { full_name: string } | null;
  barangay: { name: string; lgu: { name: string; province: string | null } | null } | null;
};
type Line = {
  line_no: number;
  section: string;
  form_type: string;
  form_name: string;
  series: string | null;
  beg_qty: number; beg_from: number | null; beg_to: number | null;
  rec_qty: number; rec_from: number | null; rec_to: number | null;
  iss_qty: number; iss_from: number | null; iss_to: number | null;
  end_qty: number; end_from: number | null; end_to: number | null;
};

const KIND: Record<string, string> = { cash_ticket: "Cash Tickets", official_receipt: "Official Receipts", check: "Checks" };

function Cells({ qty, from, to }: { qty: number; from: number | null; to: number | null }) {
  return (
    <>
      <td className="num">{qty || ""}</td>
      <td className="num">{from ?? ""}</td>
      <td className="num">{to ?? ""}</td>
    </>
  );
}

function Section({ title, kinds, lines }: { title: string; kinds: string[]; lines: Line[] }) {
  return (
    <>
      <tr>
        <td colSpan={13}>
          <strong>{title}</strong>
        </td>
      </tr>
      {kinds.map((k) => {
        const rows = lines.filter((l) => l.form_type === k);
        return [
          <tr key={k}>
            <td className="indent">{KIND[k]}</td>
            <td colSpan={12}></td>
          </tr>,
          ...rows.map((l) => (
            <tr key={l.line_no}>
              <td className="indent">{l.series ?? l.form_name}</td>
              <Cells qty={l.beg_qty} from={l.beg_from} to={l.beg_to} />
              <Cells qty={l.rec_qty} from={l.rec_from} to={l.rec_to} />
              <Cells qty={l.iss_qty} from={l.iss_from} to={l.iss_to} />
              <Cells qty={l.end_qty} from={l.end_from} to={l.end_to} />
            </tr>
          )),
        ];
      })}
    </>
  );
}

export default async function RaafPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ ok?: string; error?: string }>;
}) {
  const { id } = await params;
  const { ok, error } = await searchParams;
  const { supabase, canWrite, roles } = await requireBarangay();

  const { data: row } = await supabase
    .from("raaf")
    .select("id, raaf_no, period_year, period_month, status, certified_at, barangay_id, treasurer:treasurer_official_id(full_name), barangay:barangay_id(name, lgu:lgu_id(name, province))")
    .eq("id", id)
    .maybeSingle();
  if (!row) notFound();
  const raaf = row as unknown as Raaf;
  const certified = raaf.status === "certified";

  // A draft is worked out live; a certified report shows the lines as certified.
  const { data: lineRows } = certified
    ? await supabase.from("raaf_line").select("*").eq("raaf_id", id).order("line_no")
    : await supabase.rpc("raaf_compute", { p_barangay: raaf.barangay_id, p_year: raaf.period_year, p_month: raaf.period_month });
  const lines = (lineRows ?? []) as Line[];
  const lgu = raaf.barangay?.lgu;
  const month = `${MONTHS[raaf.period_month - 1]} ${raaf.period_year}`;

  return (
    <>
      <style>{`@page { size: A4 landscape; margin: 10mm; }`}</style>
      <header className="row no-print">
        <div>
          <h1>RAAF {raaf.raaf_no ?? "(draft)"}</h1>
          <p className="muted">
            <Link href="/forms/raaf">All RAAFs</Link> · {month} · {certified ? "Certified" : "Draft, worked out from the booklets as they stand now"}
          </p>
        </div>
        <div className="actions">
          <PrintButton />
          {canWrite && !certified && (
            <>
              {roles.has("barangay_treasurer") && (
                <form action={certifyRaaf}>
                  <input type="hidden" name="id" value={raaf.id} />
                  <button type="submit">Certify (Treasurer)</button>
                </form>
              )}
              <form action={deleteRaaf}>
                <input type="hidden" name="id" value={raaf.id} />
                <button type="submit" className="secondary">Delete draft</button>
              </form>
            </>
          )}
        </div>
      </header>
      <Flash ok={ok} error={error} />

      <article className="annex">
        <div className="annex-tag">Annex 18</div>
        <h2 className="annex-title">
          REPORT OF ACCOUNTABILITY FOR ACCOUNTABLE FORMS
          <br />
          <span style={{ fontWeight: 400, fontSize: 12 }}>For the Month of {month}</span>
        </h2>
        <div className="annex-head">
          <div>
            <div>Barangay: <u>{raaf.barangay?.name}</u></div>
            <div>Barangay Treasurer: <u>{raaf.treasurer?.full_name ?? ""}</u></div>
          </div>
          <div>
            <div>City/Municipality: <u>{lgu?.name}</u></div>
            <div>Province: <u>{lgu?.province ?? ""}</u></div>
          </div>
          <div>
            <div>RAAF No.: <u>{raaf.raaf_no ?? "—"}</u></div>
          </div>
        </div>

        <table className="annex-table small">
          <thead>
            <tr>
              <th rowSpan={3}>Name of Form</th>
              <th colSpan={3}>Beginning Balance</th>
              <th colSpan={3}>Receipt</th>
              <th colSpan={3}>Issued</th>
              <th colSpan={3}>Ending Balance</th>
            </tr>
            <tr>
              {[0, 1, 2, 3].map((i) => [
                <th key={`q${i}`} rowSpan={2}>QTY</th>,
                <th key={`s${i}`} colSpan={2}>Inclusive Serial Nos.</th>,
              ])}
            </tr>
            <tr>
              {[0, 1, 2, 3].map((i) => [<th key={`f${i}`}>From</th>, <th key={`t${i}`}>To</th>])}
            </tr>
          </thead>
          <tbody>
            <Section title="A. With Money Value" kinds={["cash_ticket"]} lines={lines} />
            <Section title="B. Without Money Value" kinds={["official_receipt", "check"]} lines={lines} />
          </tbody>
        </table>

        <div className="annex-box">
          <strong>CERTIFICATION:</strong>
          <p>
            I hereby certify that the foregoing is a true statement of all accountable forms received, issued and transferred by
            me during the above-stated period and the correctness of the beginning balances.
          </p>
          <div className="sig-row">
            <div className="sig">
              <div className="sig-line">{raaf.treasurer?.full_name ?? ""}</div>
              <div className="sig-label">(Name and Signature) Barangay Treasurer</div>
            </div>
            <div className="sig">
              <div className="sig-line">{raaf.certified_at ? formatDate(raaf.certified_at.slice(0, 10)) : ""}</div>
              <div className="sig-label">Date</div>
            </div>
          </div>
        </div>
      </article>

      <p className="muted no-print">
        Three copies: original to the COA Auditor, second to the C/M Accountant, third for the Treasurer. Add it to section C of the
        month&apos;s <Link href="/disbursements/transmittal">Transmittal Letter</Link>.
      </p>
    </>
  );
}
