import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

// Everything a page needs to know about who is signed in and which barangay
// they are working on. Accountants cover several barangays and pick one; the
// choice is kept in a cookie. Barangay officers only ever see their own.

export type Membership = {
  role: string;
  lgu_id: string;
  barangay_id: string | null;
  lgu: { name: string; lgu_type: string } | null;
  barangay: { name: string } | null;
};

export type BarangayRef = { id: string; name: string; lgu_id: string };

const LGU_STAFF = ["lgu_accountant", "lgu_bookkeeper", "lgu_admin"];

export async function getAppContext() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const [{ data: membershipRows }, { data: barangayRows }] = await Promise.all([
    supabase
      .from("user_membership")
      .select("role, lgu_id, barangay_id, lgu:lgu_id(name, lgu_type), barangay:barangay_id(name)")
      .eq("user_id", user.id)
      .eq("is_active", true),
    supabase.from("barangay").select("id, name, lgu_id").eq("is_active", true).order("name"),
  ]);

  const memberships = (membershipRows ?? []) as unknown as Membership[];
  const barangays = (barangayRows ?? []) as BarangayRef[];

  const cookieStore = await cookies();
  const wanted = cookieStore.get("barangay_id")?.value;
  const barangay = barangays.find((b) => b.id === wanted) ?? barangays[0] ?? null;

  const isLguStaff = memberships.some((m) => LGU_STAFF.includes(m.role));
  const isAuditorOnly = memberships.length > 0 && memberships.every((m) => m.role === "coa_auditor");

  return {
    supabase,
    user,
    memberships,
    barangays,
    barangay,
    isLguStaff,
    canWrite: !isAuditorOnly && memberships.length > 0,
  };
}

// Pages that work on one barangay call this; it sends people with no
// barangay back home with an explanation.
export async function requireBarangay() {
  const ctx = await getAppContext();
  if (!ctx.barangay) redirect("/?error=" + encodeURIComponent("Your account is not linked to any barangay yet."));
  return { ...ctx, barangay: ctx.barangay };
}
