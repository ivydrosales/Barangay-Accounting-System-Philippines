import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Barangay Accounting System",
  description:
    "Digital books for Philippine barangays, following the COA Manual on the Financial Management of Barangays (2018).",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
