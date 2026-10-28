// Shows the result of the last action. Server actions redirect back to the
// page with ?ok= or ?error= so nothing depends on client-side JavaScript.
export function Flash({ ok, error }: { ok?: string; error?: string }) {
  if (error) return <p className="flash error no-print">{error}</p>;
  if (ok) return <p className="flash ok no-print">{ok}</p>;
  return null;
}
