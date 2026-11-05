import { describe, it, expect } from 'vitest';
import { encodeFields, decodeFields, nestDotted, quoteFieldPath } from '../src/firestore';
import { verifyPaystackSignature, paymentReference, parseReference } from '../src/paystack';
import { usdToBaseUnits, pickFundingTokens } from '../src/oneclick';
import { buildPolicy, daoName } from '../src/dao';

describe('firestore encoding', () => {
  it('round-trips values', () => {
    const d = new Date('2026-11-01T10:00:00Z');
    const obj = { a: 1, b: 1.5, c: 'x', d: true, e: null, f: [1, 'y'], g: { h: d } };
    expect(decodeFields(encodeFields(obj))).toEqual(obj);
    expect(encodeFields({ n: 5 }).n).toEqual({ integerValue: '5' });
  });
  it('nests dotted paths and quotes odd segments', () => {
    expect(nestDotted({ 'a.b': 1, c: 2 })).toEqual({ a: { b: 1 }, c: 2 });
    expect(quoteFieldPath('contributedNgn.9abc')).toBe('contributedNgn.`9abc`');
    expect(quoteFieldPath('purposes.food.spentNgn')).toBe('purposes.food.spentNgn');
  });
});

describe('paystack', () => {
  it('verifies HMAC-SHA512 signatures', async () => {
    const body = '{"event":"transfer.success"}';
    const key = await crypto.subtle.importKey('raw', new TextEncoder().encode('sk_test_abc'), { name: 'HMAC', hash: 'SHA-512' }, false, ['sign']);
    const sig = Array.from(new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(body))), b => b.toString(16).padStart(2, '0')).join('');
    expect(await verifyPaystackSignature('sk_test_abc', body, sig)).toBe(true);
    expect(await verifyPaystackSignature('sk_test_abc', body + ' ', sig)).toBe(false);
  });
  it('references are valid and reversible', () => {
    const ref = paymentReference('abcdefghij0123456789', 'zyxwvutsrq9876543210');
    expect(ref.length).toBeLessThanOrEqual(50);
    expect(ref).toMatch(/^[a-z0-9_-]{16,50}$/);
    expect(parseReference(ref)).toEqual({ familyId: 'abcdefghij0123456789', paymentId: 'zyxwvutsrq9876543210' });
  });
});

describe('1click + dao helpers', () => {
  it('converts USD to base units', () => {
    expect(usdToBaseUnits(50, 1, 6)).toBe('50000000');
    expect(usdToBaseUnits(30, 3000, 18)).toBe('10000000000000000');
  });
  it('picks a clean token list', () => {
    const all = [{ assetId: 'a', symbol: 'USDC', blockchain: 'base', decimals: 6, price: 1 }, { assetId: 'b', symbol: 'DOGE', blockchain: 'doge', decimals: 8, price: 0.1 }];
    expect(pickFundingTokens(all).map(t => t.assetId)).toEqual(['a']);
  });
  it('builds a guardian-limited policy and valid DAO names', () => {
    const p = buildPolicy({ councilAccount: 'op.testnet', guardianAccount: 'g.testnet', proposalBondYocto: 10n ** 23n });
    expect(p.roles[0]).toMatchObject({ name: 'guardian', permissions: ['transfer:VoteApprove', 'transfer:VoteReject'] });
    expect(() => buildPolicy({ councilAccount: 'a', guardianAccount: 'a', proposalBondYocto: 1n })).toThrow();
    expect(daoName('The Okonkwo Family!!', 'ab12')).toBe('pm-the-okonkwo-family-ab12');
  });
});
