import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { signOut } from "./login/actions";

// Plain-language names for the roles in app_role (see migration 1).
const ROLE_LABELS: Record<string, string> = {
  punong_barangay: "Punong Barangay",
  barangay_treasurer: "Barangay Treasurer",
  cca: "Chairman, Committee on Appropriations",
  barangay_secretary: "Barangay Secretary",
  sk_chairperson: "SK Chairperson",
  deputized_collector: "Deputized Collector",
  property_custodian: "Property Custodian",
  petty_cash_custodian: "Petty Cash Custodian",
  lgu_accountant: "City/Municipal Accountant",
  lgu_bookkeeper: "Bookkeeper",
  lgu_admin: "LGU Administrator",
  coa_auditor: "COA Auditor (read-only)",
};

type Membership = {
  role: string;
  lgu: { name: string; lgu_type: string } | null;
  barangay: { name: string } | null;
};

type BarangayRow = {
  id: string;
  name: string;
  fund: { code: string; name: string }[];
};

export default async function Home() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const [{ data: membershipRows }, { count: accountCount }, { data: barangayRows }] =
    await Promise.all([
      supabase
        .from("user_membership")
        .select("role, lgu:lgu_id(name, lgu_type), barangay:barangay_id(name)")
        .eq("user_id", user.id)
        .eq("is_active", true),
      supabase.from("account").select("code", { count: "exact", head: true }),
      supabase.from("barangay").select("id, name, fund(code, name)").order("name"),
    ]);

  const memberships = (membershipRows ?? []) as unknown as Membership[];
  const barangays = (barangayRows ?? []) as unknown as BarangayRow[];

  return (
    <main>
      <header className="row">
        <div>
          <h1>Barangay Accounting System</h1>
          <p className="muted">Signed in as {user.email}</p>
        </div>
        <form action={signOut}>
          <button type="submit" className="secondary">
            Sign out
          </button>
        </form>
      </header>

      <section className="card">
        <h2>Your access</h2>
        {memberships.length === 0 ? (
          <p>
            Your account has no role yet. Ask your LGU administrator to add you to a
            barangay or to the Accountant&apos;s office.
          </p>
        ) : (
          <ul>
            {memberships.map((m, i) => (
              <li key={i}>
                <strong>{ROLE_LABELS[m.role] ?? m.role}</strong>
                {m.barangay ? ` · ${m.barangay.name}` : " · all barangays"}
                {m.lgu ? ` · ${m.lgu.name}` : ""}
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className="card">
        <h2>Barangays and funds</h2>
        {barangays.length === 0 ? (
          <p>No barangays are visible to you yet.</p>
        ) : (
          barangays.map((b) => (
            <div key={b.id} className="stack-sm">
              <h3>{b.name}</h3>
              <ul className="inline">
                {b.fund.map((f) => (
                  <li key={f.code} title={f.name}>
                    {f.code}
                  </li>
                ))}
              </ul>
            </div>
          ))
        )}
      </section>

      <section className="card">
        <h2>Chart of accounts</h2>
        <p>
          {accountCount ?? 0} COA accounts loaded (Manual on the Financial Management of
          Barangays, 2018, Chapter XIII).
        </p>
      </section>

      <p className="muted">
        Phase 0 (foundation). Collections, the Cashbook and Disbursement Vouchers come in
        Phase 1.
      </p>
    </main>
  );
}
