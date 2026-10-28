// Section C of the RCD (Annex 9) and RCR (Annex 9.1): accountable forms on
// hand, received, issued and remaining, with their serial ranges. Rows come
// from the database function report_accountable_forms().

export type AccountableFormRow = {
  form_name: string;
  series: string | null;
  beg_qty: number; beg_from: number | null; beg_to: number | null;
  rec_qty: number; rec_from: number | null; rec_to: number | null;
  iss_qty: number; iss_from: number | null; iss_to: number | null;
  end_qty: number; end_from: number | null; end_to: number | null;
};

const range = (from: number | null, to: number | null, qty: number) =>
  qty > 0 && from !== null && to !== null ? `${from}–${to}` : "";

export function AccountableForms({ rows }: { rows: AccountableFormRow[] }) {
  return (
    <table className="annex-table small">
      <thead>
        <tr>
          <th rowSpan={2}>Name of Form and No.</th>
          <th colSpan={2}>Beginning Balance</th>
          <th colSpan={2}>Receipt</th>
          <th colSpan={2}>Issued</th>
          <th colSpan={2}>Ending Balance</th>
        </tr>
        <tr>
          <th>Qty</th><th>Inclusive Serial No.</th>
          <th>Qty</th><th>Inclusive Serial No.</th>
          <th>Qty</th><th>Inclusive Serial No.</th>
          <th>Qty</th><th>Inclusive Serial No.</th>
        </tr>
      </thead>
      <tbody>
        {rows.length === 0 ? (
          <tr><td colSpan={9} className="muted">No accountable forms on record</td></tr>
        ) : (
          rows.map((r, i) => (
            <tr key={i}>
              <td>{r.form_name}{r.series ? ` (${r.series})` : ""}</td>
              <td className="num">{r.beg_qty || ""}</td><td>{range(r.beg_from, r.beg_to, r.beg_qty)}</td>
              <td className="num">{r.rec_qty || ""}</td><td>{range(r.rec_from, r.rec_to, r.rec_qty)}</td>
              <td className="num">{r.iss_qty || ""}</td><td>{range(r.iss_from, r.iss_to, r.iss_qty)}</td>
              <td className="num">{r.end_qty || ""}</td><td>{range(r.end_from, r.end_to, r.end_qty)}</td>
            </tr>
          ))
        )}
      </tbody>
    </table>
  );
}
