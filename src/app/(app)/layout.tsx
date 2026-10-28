import Link from "next/link";
import { getAppContext } from "@/lib/context";
import { signOut } from "@/app/login/actions";
import { setBarangay } from "./actions";

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const ctx = await getAppContext();

  return (
    <>
      <nav className="topnav no-print">
        <Link href="/" className="brand">
          Barangay Accounting
        </Link>
        <div className="links">
          <Link href="/collections">Official Receipts</Link>
          <Link href="/collections/rcr">RCR</Link>
          <Link href="/collections/rcd">RCD</Link>
          <Link href="/cashbook">Cashbook</Link>
          <Link href="/disbursements">DVs</Link>
          <Link href="/disbursements/checks">Checks</Link>
          <Link href="/disbursements/transmittal">Transmittal</Link>
          <Link href="/forms">Forms</Link>
          <Link href="/forms/raaf">RAAF</Link>
          <Link href="/parallel-run">Parallel run</Link>
        </div>
        <div className="right">
          {ctx.barangays.length > 1 ? (
            <form action={setBarangay} className="inline-form">
              <select name="barangay_id" defaultValue={ctx.barangay?.id} aria-label="Barangay">
                {ctx.barangays.map((b) => (
                  <option key={b.id} value={b.id}>
                    {b.name}
                  </option>
                ))}
              </select>
              <button type="submit" className="secondary small">
                Switch
              </button>
            </form>
          ) : (
            <span className="muted">{ctx.barangay?.name ?? "No barangay"}</span>
          )}
          <form action={signOut}>
            <button type="submit" className="secondary small">
              Sign out
            </button>
          </form>
        </div>
      </nav>
      <main>{children}</main>
    </>
  );
}
