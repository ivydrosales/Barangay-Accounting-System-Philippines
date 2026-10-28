// Money and dates the way the forms show them. Amounts arrive from Postgres
// as strings (numeric), never as floats.

const peso = new Intl.NumberFormat("en-PH", { style: "currency", currency: "PHP", minimumFractionDigits: 2 });
const plain = new Intl.NumberFormat("en-PH", { minimumFractionDigits: 2, maximumFractionDigits: 2 });

export function formatPeso(value: string | number | null | undefined): string {
  if (value === null || value === undefined || value === "") return "";
  return peso.format(Number(value));
}

// Without the sign, for columns inside a form that already says "Amount".
export function formatAmount(value: string | number | null | undefined): string {
  if (value === null || value === undefined || value === "") return "";
  const n = Number(value);
  if (n === 0) return "";
  return plain.format(n);
}

export function formatDate(value: string | null | undefined): string {
  if (!value) return "";
  const [y, m, d] = value.slice(0, 10).split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d)).toLocaleDateString("en-PH", {
    year: "numeric",
    month: "short",
    day: "numeric",
    timeZone: "UTC",
  });
}

export function formatDateTime(value: string | null | undefined): string {
  if (!value) return "";
  return new Date(value).toLocaleString("en-PH", { timeZone: "Asia/Manila", dateStyle: "medium", timeStyle: "short" });
}

// YYYY-MM-DD in Manila, for date inputs and defaults.
export function todayManila(): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Manila" }).format(new Date());
}

export const MONTHS = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December",
];

export function sum(values: Array<string | number | null | undefined>): number {
  return values.reduce<number>((acc, v) => acc + (v ? Number(v) : 0), 0);
}
