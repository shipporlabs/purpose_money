import { describe, it, expect } from 'vitest';
import { evaluate, nameMatch, DEFAULT_RULES, DEFAULT_PURPOSES, requiredApprovals, lagosDayStart, GuardianInput } from '../src/guardian';

const now = Date.UTC(2026, 10, 5, 12);
const base = (): GuardianInput => ({
  amountNgn: 45_000, category: 'food', potReady: true,
  merchant: { status: 'approved', category: 'food', approvedAtMs: now - 48 * 3_600_000, nameMatch: 1 },
  family: { balanceNgn: 300_000, purposes: structuredClone(DEFAULT_PURPOSES), rules: { ...DEFAULT_RULES } },
  merchantPaidTodayNgn: 0, familyPaymentsToday: 0, recentAmountsAtMerchant: [40_000, 50_000, 45_000], nowMs: now,
});

describe('guardian rules', () => {
  it('approves a normal payment', () => {
    const d = evaluate(base());
    expect(d.outcome).toBe('approved');
    expect(d.checks.every(c => c.passed)).toBe(true);
  });
  it('blocks unapproved shops (stolen phone case)', () => {
    const i = base(); i.merchant.status = 'pending'; i.amountNgn = 250_000;
    const d = evaluate(i);
    expect(d.outcome).toBe('blocked');
    expect(d.reason).toMatch(/not been approved/);
  });
  it('blocks over-budget payments', () => {
    const i = base(); i.family.purposes.food.spentNgn = 90_000;
    expect(evaluate(i).outcome).toBe('blocked');
  });
  it('blocks when the pot is empty or not live', () => {
    expect(evaluate({ ...base(), family: { ...base().family, balanceNgn: 1000 } }).outcome).toBe('blocked');
    expect(evaluate({ ...base(), potReady: false }).outcome).toBe('blocked');
  });
  it('escalates above the auto-approve limit', () => {
    const i = base(); i.family.purposes.school.budgetNgn = 500_000; i.category = 'school'; i.amountNgn = 120_000;
    i.recentAmountsAtMerchant = [];
    const d = evaluate(i);
    expect(d.outcome).toBe('escalated');
    expect(d.checks.find(c => c.id === 'auto_limit')!.passed).toBe(false);
  });
  it('escalates on daily cap, count, cooldown, name mismatch and unusual amounts', () => {
    expect(evaluate({ ...base(), merchantPaidTodayNgn: 140_000 }).outcome).toBe('escalated');
    expect(evaluate({ ...base(), familyPaymentsToday: 6 }).outcome).toBe('escalated');
    const c = base(); c.family.rules.newMerchantCooldownHours = 72; expect(evaluate(c).outcome).toBe('escalated');
    const n = base(); n.merchant.nameMatch = 0.2; expect(evaluate(n).outcome).toBe('escalated');
    const u = base(); u.recentAmountsAtMerchant = [5_000, 6_000, 5_500]; u.amountNgn = 40_000; expect(evaluate(u).outcome).toBe('escalated');
  });
});

describe('helpers', () => {
  it('matches names sensibly', () => {
    expect(nameMatch('Mama Nkechi Stores', 'NKECHI OKAFOR')).toBe(1);
    expect(nameMatch('Bright Future School', 'BRIGHT FUTURE INTL SCHOOL LTD')).toBe(1);
    expect(nameMatch('Mama Nkechi Stores', 'JOHN DOE')).toBe(0);
  });
  it('required approvals never exceed sibling count', () => {
    expect(requiredApprovals(DEFAULT_RULES, 1)).toBe(1);
    expect(requiredApprovals(DEFAULT_RULES, 3)).toBe(2);
  });
  it('computes the Lagos day boundary', () => {
    const t = Date.UTC(2026, 10, 5, 23, 30); // 00:30 on Nov 6 in Lagos
    expect(new Date(lagosDayStart(t)).toISOString()).toBe('2026-11-05T23:00:00.000Z');
  });
});
