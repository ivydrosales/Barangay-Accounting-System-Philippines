// Plain-language names for the states a document passes through.

export const DV_STATUS: Record<string, string> = {
  draft: "Draft · awaiting Box A (CCA)",
  certified_a: "Box A signed · awaiting Box B (Treasurer)",
  certified_b: "Box B signed · awaiting Box C (Punong Barangay)",
  approved: "Approved · awaiting check",
  check_issued: "Check drawn · awaiting payee (Box D)",
  paid: "Paid",
  cancelled: "Cancelled",
};

export const CHECK_STATUS: Record<string, string> = {
  issued: "Issued, not yet released",
  released: "Released to payee",
  cleared: "Cleared by the bank",
  stale: "Stale (6 months unpresented)",
  spoiled: "Spoiled",
  cancelled: "Cancelled",
};

export const TL_STATUS: Record<string, string> = {
  draft: "Draft",
  submitted: "Submitted to the Accountant",
  received: "Received by the Accountant",
};

export const FORM_TYPE: Record<string, string> = {
  official_receipt: "Official Receipt (Accountable Form No. 51)",
  cash_ticket: "Cash Ticket",
  check: "Check booklet",
};

export const FORM_STATUS: Record<string, string> = {
  on_hand: "On hand",
  in_use: "In use",
  used_up: "Used up",
  returned: "Returned",
  lost: "Lost",
};

// Plain-language names for the roles in app_role (see migration 1).
export const ROLE_LABELS: Record<string, string> = {
  punong_barangay: "Punong Barangay",
  barangay_treasurer: "Barangay Treasurer",
  cca: "Chairman, Committee on Appropriations",
  barangay_secretary: "Barangay Secretary",
  sk_chairperson: "SK Chairperson",
  deputized_collector: "Deputized Barangay Collector",
  property_custodian: "Property Custodian",
  petty_cash_custodian: "Petty Cash Custodian",
  lgu_accountant: "City/Municipal Accountant",
  lgu_bookkeeper: "Bookkeeper",
  lgu_admin: "LGU Administrator",
  coa_auditor: "COA Auditor (read-only)",
};
