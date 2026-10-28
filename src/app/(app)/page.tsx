import Link from "next/link";
import { Flash } from "@/components/Flash";
import { getAppContext } from "@/lib/context";
import { ROLE_LABELS } from "@/lib/labels";

type BarangayRow = { id: string; name: string; fund: { code: string; name: string }[] };

export default async function Home({ searchParams }: { searchParams: Promise<{ ok?: string; error?: string }> }) {
  const { ok, error } = await searchParams;
  const { supabase, user, memberships } = await getAppContext();

  const [{ count: accountCount }, { data: barangayRows }] = await Promise.all([
    supabase.from("account").select("code", { count: "exact", head: true }),
    supabase.from("barangay").select("id, name, fund(code, name)").order("name"),
  ]);
  const barangays = (barangayRows ?? []) as unknown as BarangayRow[];

  return (
    <>
      <header className="row">
        <div>
          <h1>Home</h1>
          <p className="muted">Signed in as {user.email}</p>
        </div>
      </header>
      <Flash ok={ok} error={error} />

      <section className="card">
        <h2>Your access</h2>
        {memberships.length === 0 ? (
          <p>
            Your account has no role yet. Ask your LGU administrator to add you to a barangay or to the
            Accountant&apos;s office.
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
        <h2>Collections</h2>
        <p>
          Issue <Link href="/collections">Official Receipts</Link>, turn collectors&apos; receipts over on an{" "}
          <Link href="/collections/rcr">RCR</Link>, report the day on an <Link href="/collections/rcd">RCD</Link>, and
          keep the <Link href="/cashbook">Cashbook</Link> up to date.
        </p>
      </section>

      <section className="card">
        <h2>Disbursements</h2>
        <p>
          Prepare <Link href="/disbursements">Disbursement Vouchers</Link> and walk them through Boxes A, B and C, draw checks
          and print the Punong Barangay Certification from the <Link href="/disbursements/checks">check register</Link>, and send
          the month&apos;s paid vouchers and RCDs to the Accountant on a <Link href="/disbursements/transmittal">Transmittal Letter</Link>.
          Booklets of ORs and checks are recorded under <Link href="/forms">Accountable forms</Link>.
        </p>
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
          {accountCount ?? 0} COA accounts loaded (Manual on the Financial Management of Barangays, 2018, Chapter
          XIII).
        </p>
      </section>
    </>
  );
}
