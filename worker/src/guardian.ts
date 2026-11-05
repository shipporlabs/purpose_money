// The guardian's rule engine. Pure functions, no I/O, fully unit-tested.
// Rules decide; the optional AI note only explains.

export interface Purpose { label: string; budgetNgn: number; spentNgn: number }
export interface Rules {
  autoApproveLimitNgn: number;
  dailyCapPerMerchantNgn: number;
  newMerchantCooldownHours: number;
  maxPaymentsPerDay: number;
  siblingApprovalsRequired: number;
}
export const DEFAULT_RULES: Rules = {
  autoApproveLimitNgn: 100_000,
  dailyCapPerMerchantNgn: 150_000,
  newMerchantCooldownHours: 0,
  maxPaymentsPerDay: 6,
  siblingApprovalsRequired: 2,
};
export const DEFAULT_PURPOSES: Record<string, Purpose> = {
  food: { label: 'Food', budgetNgn: 100_000, spentNgn: 0 },
  rent: { label: 'Rent', budgetNgn: 60_000, spentNgn: 0 },
  school: { label: 'School fees', budgetNgn: 120_000, spentNgn: 0 },
};

export interface GuardianInput {
  amountNgn: number;
  category: string;
  potReady: boolean;
  merchant: { status: string; category: string; approvedAtMs: number | null; nameMatch: number };
  family: { balanceNgn: number; purposes: Record<string, Purpose>; rules: Rules };
  merchantPaidTodayNgn: number;
  familyPaymentsToday: number;
  recentAmountsAtMerchant: number[];
  nowMs: number;
}

export type Outcome = 'approved' | 'escalated' | 'blocked';
export interface Check { id: string; label: string; passed: boolean; severity: 'block' | 'escalate'; detail: string }
export interface Decision { outcome: Outcome; checks: Check[]; reason: string; riskScore: number }

const ngn = (n: number) => '₦' + Math.round(n).toLocaleString('en-NG');

export function median(xs: number[]): number {
  if (!xs.length) return 0;
  const s = [...xs].sort((a, b) => a - b);
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}

export function evaluate(i: GuardianInput): Decision {
  const checks: Check[] = [];
  const add = (id: string, label: string, passed: boolean, severity: Check['severity'], detail: string) =>
    checks.push({ id, label, passed, severity, detail });

  const purpose = i.family.purposes[i.category];
  const remaining = purpose ? purpose.budgetNgn - purpose.spentNgn : 0;
  const r = i.family.rules;

  add('pot_ready', 'Family pot is live on NEAR', i.potReady, 'block',
    i.potReady ? 'The family DAO is active.' : 'The family pot is still being set up on NEAR.');
  add('merchant_approved', 'Approved shop', i.merchant.status === 'approved', 'block',
    i.merchant.status === 'approved' ? 'The family approved this shop.' : 'This shop has not been approved by the family.');
  add('purpose_exists', 'Valid purpose', !!purpose, 'block',
    purpose ? `Paid from ${purpose.label}.` : `There is no "${i.category}" budget.`);
  add('purpose_budget', 'Within purpose budget', !!purpose && remaining >= i.amountNgn, 'block',
    purpose ? `${ngn(Math.max(remaining, 0))} left in ${purpose.label}.` : 'No budget to spend from.');
  add('pot_balance', 'Enough money in the pot', i.family.balanceNgn >= i.amountNgn, 'block',
    `Pot balance is ${ngn(i.family.balanceNgn)}.`);

  add('auto_limit', 'Under auto-approve limit', i.amountNgn <= r.autoApproveLimitNgn, 'escalate',
    `Auto-approve limit is ${ngn(r.autoApproveLimitNgn)}.`);
  add('daily_cap', 'Under daily cap for this shop', i.merchantPaidTodayNgn + i.amountNgn <= r.dailyCapPerMerchantNgn, 'escalate',
    `${ngn(i.merchantPaidTodayNgn)} already paid here today; cap is ${ngn(r.dailyCapPerMerchantNgn)}.`);
  add('daily_count', 'Normal number of payments today', i.familyPaymentsToday < r.maxPaymentsPerDay, 'escalate',
    `${i.familyPaymentsToday} payment(s) today; limit is ${r.maxPaymentsPerDay}.`);

  const ageH = i.merchant.approvedAtMs === null ? 0 : (i.nowMs - i.merchant.approvedAtMs) / 3_600_000;
  const cooled = r.newMerchantCooldownHours <= 0 || ageH >= r.newMerchantCooldownHours;
  add('cooldown', 'Shop past its cooling-off period', cooled, 'escalate',
    cooled ? 'Shop has been approved long enough.' : `New shop: ${r.newMerchantCooldownHours}h cooling-off not over.`);

  const nameOk = i.merchant.nameMatch >= 0.5;
  add('name_match', 'Bank name matches the shop', nameOk, 'escalate',
    nameOk ? 'Bank account name matches the shop name.' : 'Bank account name looks different from the shop name.');

  const med = median(i.recentAmountsAtMerchant);
  const unusual = i.recentAmountsAtMerchant.length >= 3 && i.amountNgn > med * 3;
  add('unusual_amount', 'Amount looks normal for this shop', !unusual, 'escalate',
    unusual ? `About ${Math.round(i.amountNgn / med)}× the usual ${ngn(med)} here.` : 'In line with past payments here.');

  const failedBlock = checks.find(c => !c.passed && c.severity === 'block');
  const failedEscalate = checks.find(c => !c.passed && c.severity === 'escalate');
  const failedCount = checks.filter(c => !c.passed).length;
  const riskScore = Math.min(100, checks.filter(c => !c.passed).reduce((s, c) => s + (c.severity === 'block' ? 50 : 20), 0));

  if (failedBlock) return { outcome: 'blocked', checks, reason: failedBlock.detail, riskScore };
  if (failedEscalate) return {
    outcome: 'escalated', checks, riskScore,
    reason: failedCount > 1 ? `${failedEscalate.detail} (+${failedCount - 1} more)` : failedEscalate.detail,
  };
  return { outcome: 'approved', checks, reason: 'Every rule passed.', riskScore };
}

/** Similarity between the name the family typed and the bank's account name (0..1). */
export function nameMatch(typed: string, accountName: string): number {
  const stop = new Set(['the', 'and', 'ltd', 'limited', 'nig', 'nigeria', 'enterprises', 'enterprise', 'ventures', 'store', 'stores', 'shop', 'mama', 'mr', 'mrs']);
  const tok = (s: string) => new Set(s.toLowerCase().replace(/[^a-z0-9 ]/g, ' ').split(/\s+/).filter(t => t.length > 1 && !stop.has(t)));
  const a = tok(typed), b = tok(accountName);
  if (!a.size || !b.size) return 0;
  let hit = 0;
  for (const t of a) if ([...b].some(u => u === t || (t.length >= 4 && (u.startsWith(t) || t.startsWith(u))))) hit++;
  return Math.round((hit / Math.min(a.size, b.size)) * 100) / 100;
}

export function requiredApprovals(rules: Rules, siblingCount: number): number {
  return Math.max(1, Math.min(rules.siblingApprovalsRequired, siblingCount));
}

/** Start of "today" in Lagos time (UTC+1), as epoch ms. */
export function lagosDayStart(nowMs: number): number {
  const offset = 3_600_000;
  return Math.floor((nowMs + offset) / 86_400_000) * 86_400_000 - offset;
}
