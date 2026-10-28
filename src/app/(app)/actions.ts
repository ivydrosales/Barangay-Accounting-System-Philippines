"use server";

import { cookies } from "next/headers";
import { revalidatePath } from "next/cache";
import { field } from "@/lib/actions";

export async function setBarangay(formData: FormData) {
  const id = field(formData, "barangay_id");
  const cookieStore = await cookies();
  cookieStore.set("barangay_id", id, { path: "/", sameSite: "lax", maxAge: 60 * 60 * 24 * 365 });
  revalidatePath("/", "layout");
}
