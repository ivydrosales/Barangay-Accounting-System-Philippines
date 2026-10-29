import Link from "next/link";
import { Flash } from "@/components/Flash";
import { requireBarangay } from "@/lib/context";
import { formatDate, formatPeso } from "@/lib/format";
import { OFFICIAL_POSITIONS } from "@/lib/labels";
import { addBankAccount, addBarangay, addOfficial, addSupplier, deactivateOfficial } from "./actions";

type Official = {
  id: string;
  position: string;
  full_name: string;
  term_start: string | null;
  term_end: string | null;
  bond_amount: string | null;
  bond_expires_on: string | null;
  is_active: boolean;
};
type Bank = { id: string; bank_name: string; branch: string | null; account_number: string; account_name: string; is_depository: boolean; closed_on: string | null };
type BarangayRow = { id: string; name: string };
type Supplier = { id: string; name: string; tin: string | null; address: string | null };

// The positions the forms need before the barangay can start.
const REQUIRED = ["Punong Barangay", "Barangay Treasurer", "Chairman, Committee on Appropriations"];

export default async function SetupPage({ searchParams }: { searchParams: Promise<{ ok?: string; error?: string }> }) {
  const { ok, error } = await searchParams;
  const { supabase, barangay, canWrite, isLguStaff, roles } = await requireBarangay();

  const [{ data: officialRows }, { data: bankRows }, { data: barangayRows }, { data: supplierRows }] = await Promise.all([
    supabase
      .from("official")
      .select("id, position, full_name, term_start, term_end, bond_amount, bond_expires_on, is_active")
      .eq("barangay_id", barangay.id)
      .order("is_active", { ascending: false })
      .order("position"),
    supabase
      .from("bank_account")
      .select("id, bank_name, branch, account_number, account_name, is_depository, closed_on")
      .eq("barangay_id", barangay.id)
      .order("bank_name"),
    supabase.from("barangay").select("id, name").eq("lgu_id", barangay.lgu_id).order("name"),
    supabase.from("supplier").select("id, name, tin, address").eq("lgu_id", barangay.lgu_id).order("name"),
  ]);
  const officials = (officialRows ?? []) as Official[];
  const banks = (bankRows ?? []) as Bank[];
  const barangays = (barangayRows ?? []) as BarangayRow[];
  const suppliers = (supplierRows ?? []) as Supplier[];
  const active = officials.filter((o) => o.is_active);
  const missing = REQUIRED.filter((p) => !active.some((o) => o.position === p));
  const hasDepository = banks.some((b) => b.is_depository && !b.closed_on);

  return (
    <>
      <header className="row">
        <div>
          <h1>Setup</h1>
          <p className="muted">
            {barangay.name} · the officials, bank account, barangays and suppliers the forms draw on
            {roles.has("lgu_admin") && (
              <>
                {" "}
                · <Link href="/setup/people">People and access</Link>
              </>
            )}
          </p>
        </div>
      </header>
      <Flash ok={ok} error={error} />

      {(missing.length > 0 || !hasDepository) && (
        <p className="flash error">
          Before {barangay.name} can start:{" "}
          {[...missing.map((p) => `add the ${p}`), ...(hasDepository ? [] : ["record the depository bank account"])].join("; ")}.
        </p>
      )}

      <section className="card">
        <h2>Officials of {barangay.name}</h2>
        <p className="muted">
          Their names print in the signature boxes of the forms. Signing a box in the app also needs a login with that role
          (see People and access).
        </p>
        {officials.length > 0 && (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Position</th>
                  <th>Name</th>
                  <th>Term</th>
                  <th className="num">Bond</th>
                  <th>Bond expires</th>
                  <th>Status</th>
                  {canWrite && <th></th>}
                </tr>
              </thead>
              <tbody>
                {officials.map((o) => (
                  <tr key={o.id} className={o.is_active ? undefined : "cancelled"}>
                    <td>{o.position}</td>
                    <td>{o.full_name}</td>
                    <td>
                      {formatDate(o.term_start)}
                      {o.term_end ? ` to ${formatDate(o.term_end)}` : ""}
                    </td>
                    <td className="num">{formatPeso(o.bond_amount)}</td>
                    <td>{formatDate(o.bond_expires_on)}</td>
                    <td>{o.is_active ? "In office" : "No longer in office"}</td>
                    {canWrite && (
                      <td>
                        {o.is_active && (
                          <form action={deactivateOfficial}>
                            <input type="hidden" name="id" value={o.id} />
                            <button type="submit" className="secondary small">
                              Left office
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
        {canWrite && (
          <form action={addOfficial} className="grid" style={{ marginTop: 12 }}>
            <input type="hidden" name="lgu_id" value={barangay.lgu_id} />
            <input type="hidden" name="barangay_id" value={barangay.id} />
            <label>
              Position
              <select name="position" required defaultValue={missing[0] ?? OFFICIAL_POSITIONS[0]}>
                {OFFICIAL_POSITIONS.map((p) => (
                  <option key={p} value={p}>
                    {p}
                  </option>
                ))}
              </select>
            </label>
            <label>
              Full name
              <input name="full_name" required placeholder="As it should print on the forms" />
            </label>
            <label>
              Term starts
              <input name="term_start" type="date" />
            </label>
            <label>
              Term ends
              <input name="term_end" type="date" />
            </label>
            <label>
              Fidelity bond (₱, Treasurer and collectors)
              <input name="bond_amount" type="number" step="0.01" min="0" />
            </label>
            <label>
              Bond expires on
              <input name="bond_expires_on" type="date" />
            </label>
            <div className="span2">
              <button type="submit">Add official</button>
            </div>
          </form>
        )}
      </section>

      <section className="card">
        <h2>Depository bank account</h2>
        <p className="muted">One current account per barangay (manual 4.1.15). Checks are drawn on it and deposits go into it.</p>
        {banks.length > 0 && (
          <ul>
            {banks.map((b) => (
              <li key={b.id}>
                {b.bank_name}
                {b.branch ? `, ${b.branch}` : ""} · {b.account_name} · No. {b.account_number}
                {b.closed_on ? ` · closed ${formatDate(b.closed_on)}` : b.is_depository ? " · depository" : ""}
              </li>
            ))}
          </ul>
        )}
        {canWrite && !hasDepository && (
          <form action={addBankAccount} className="grid">
            <input type="hidden" name="lgu_id" value={barangay.lgu_id} />
            <input type="hidden" name="barangay_id" value={barangay.id} />
            <label>
              Bank
              <input name="bank_name" required placeholder="e.g. Land Bank of the Philippines" />
            </label>
            <label>
              Branch
              <input name="branch" />
            </label>
            <label>
              Account number
              <input name="account_number" required />
            </label>
            <label>
              Account name
              <input name="account_name" required defaultValue={`Barangay ${barangay.name}`} />
            </label>
            <label>
              Opened on
              <input name="opened_on" type="date" />
            </label>
            <div className="span2">
              <button type="submit">Record bank account</button>
            </div>
          </form>
        )}
      </section>

      {isLguStaff && (
        <section className="card">
          <h2>Barangays of the city or municipality</h2>
          <ul className="inline">
            {barangays.map((b) => (
              <li key={b.id}>{b.name}</li>
            ))}
          </ul>
          <form action={addBarangay} className="inline-form" style={{ marginTop: 12 }}>
            <input type="hidden" name="lgu_id" value={barangay.lgu_id} />
            <input name="name" required placeholder="Name of the barangay" size={30} />
            <button type="submit" className="secondary small">
              Add barangay
            </button>
          </form>
        </section>
      )}

      <section className="card">
        <h2>Suppliers</h2>
        <p className="muted">Shared by every barangay of the city or municipality. A DV can name one so the creditor&apos;s ledger is kept.</p>
        {suppliers.length > 0 && (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Name</th>
                  <th>TIN</th>
                  <th>Address</th>
                </tr>
              </thead>
              <tbody>
                {suppliers.map((s) => (
                  <tr key={s.id}>
                    <td>{s.name}</td>
                    <td>{s.tin ?? ""}</td>
                    <td>{s.address ?? ""}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        {isLguStaff && (
          <form action={addSupplier} className="grid" style={{ marginTop: 12 }}>
            <input type="hidden" name="lgu_id" value={barangay.lgu_id} />
            <label>
              Name
              <input name="name" required />
            </label>
            <label>
              TIN
              <input name="tin" />
            </label>
            <label className="span2">
              Address
              <input name="address" />
            </label>
            <div className="span2">
              <button type="submit" className="secondary">
                Add supplier
              </button>
            </div>
          </form>
        )}
      </section>
    </>
  );
}
