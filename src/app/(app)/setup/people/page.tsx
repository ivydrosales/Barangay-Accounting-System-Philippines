import Link from "next/link";
import { Flash } from "@/components/Flash";
import { requireBarangay } from "@/lib/context";
import { formatDate } from "@/lib/format";
import { BARANGAY_ROLES, LGU_ROLES, ROLE_LABELS } from "@/lib/labels";
import { grantAccess, revokeAccess } from "../actions";

type Member = {
  membership_id: string;
  email: string;
  role: string;
  barangay_id: string | null;
  barangay_name: string | null;
  is_active: boolean;
  created_at: string;
};
type BarangayRow = { id: string; name: string };

export default async function PeoplePage({ searchParams }: { searchParams: Promise<{ ok?: string; error?: string }> }) {
  const { ok, error } = await searchParams;
  const { supabase, barangay, roles, isLguStaff } = await requireBarangay();
  const isAdmin = roles.has("lgu_admin");

  const [{ data: memberRows }, { data: barangayRows }] = await Promise.all([
    supabase.rpc("lgu_members", { p_lgu: barangay.lgu_id }),
    supabase.from("barangay").select("id, name").eq("lgu_id", barangay.lgu_id).order("name"),
  ]);
  const members = (memberRows ?? []) as Member[];
  const barangays = (barangayRows ?? []) as BarangayRow[];

  return (
    <>
      <header className="row">
        <div>
          <h1>People and access</h1>
          <p className="muted">
            <Link href="/setup">Setup</Link> · who may sign in, and in which role. Barangay roles see only their barangay; the
            Accountant&apos;s office sees every barangay; COA auditors can read everything and change nothing.
          </p>
        </div>
      </header>
      <Flash ok={ok} error={error} />

      {!isLguStaff ? (
        <p className="muted">Only the City/Municipal Accountant&apos;s office sees this list.</p>
      ) : (
        <>
          {isAdmin && (
            <section className="card">
              <h2>Give someone access</h2>
              <ol className="muted">
                <li>
                  Create their login in Supabase: Authentication → Users → Add user → Create new user (tick Auto Confirm User).
                  Give them the password privately.
                </li>
                <li>Enter the same email here with their role. Barangay roles need the barangay; LGU roles do not.</li>
              </ol>
              <form action={grantAccess} className="grid">
                <input type="hidden" name="lgu_id" value={barangay.lgu_id} />
                <label>
                  Email of their login
                  <input name="email" type="email" required />
                </label>
                <label>
                  Role
                  <select name="role" required defaultValue="barangay_treasurer">
                    <optgroup label="Barangay roles">
                      {BARANGAY_ROLES.map((r) => (
                        <option key={r} value={r}>
                          {ROLE_LABELS[r]}
                        </option>
                      ))}
                    </optgroup>
                    <optgroup label="City/municipality roles">
                      {LGU_ROLES.map((r) => (
                        <option key={r} value={r}>
                          {ROLE_LABELS[r]}
                        </option>
                      ))}
                    </optgroup>
                  </select>
                </label>
                <label>
                  Barangay (for barangay roles)
                  <select name="barangay_id" defaultValue={barangay.id}>
                    <option value="">None (city/municipality role)</option>
                    {barangays.map((b) => (
                      <option key={b.id} value={b.id}>
                        {b.name}
                      </option>
                    ))}
                  </select>
                </label>
                <div className="span2">
                  <button type="submit">Give access</button>
                </div>
              </form>
            </section>
          )}

          <section className="card">
            <h2>People with access</h2>
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Email</th>
                    <th>Role</th>
                    <th>Barangay</th>
                    <th>Since</th>
                    <th>Status</th>
                    {isAdmin && <th></th>}
                  </tr>
                </thead>
                <tbody>
                  {members.map((m) => (
                    <tr key={m.membership_id} className={m.is_active ? undefined : "cancelled"}>
                      <td>{m.email}</td>
                      <td>{ROLE_LABELS[m.role] ?? m.role}</td>
                      <td>{m.barangay_name ?? "All barangays"}</td>
                      <td>{formatDate(m.created_at.slice(0, 10))}</td>
                      <td>{m.is_active ? "Active" : "Removed"}</td>
                      {isAdmin && (
                        <td>
                          {m.is_active && (
                            <form action={revokeAccess}>
                              <input type="hidden" name="id" value={m.membership_id} />
                              <button type="submit" className="secondary small">
                                Remove
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
          </section>
        </>
      )}
    </>
  );
}
