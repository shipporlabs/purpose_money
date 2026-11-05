// End-to-end handler flow with in-memory fakes for Firestore, NEAR, Paystack and 1Click.
import { describe, it, expect, beforeEach } from 'vitest';
import { App, Env } from '../src/app';
import { FirestoreError, nestDotted } from '../src/firestore';
import { generateKeyPair } from '../src/near';
import * as h from '../src/handlers';

// ---------- fakes ----------
class FakeFs {
  docs = new Map<string, { data: any; v: number }>();
  private v = 0;
  private merge(target: any, src: any) {
    for (const [k, val] of Object.entries(src)) {
      if (val && typeof val === 'object' && !Array.isArray(val) && !(val instanceof Date)) {
        target[k] = target[k] && typeof target[k] === 'object' ? target[k] : {};
        this.merge(target[k], val);
      } else target[k] = val;
    }
  }
  async get(path: string) {
    const d = this.docs.get(path);
    return d ? { id: path.split('/').pop()!, path, data: structuredClone(d.data), updateTime: String(d.v) } : null;
  }
  async create(path: string, data: any) {
    if (this.docs.has(path)) throw new FirestoreError('exists', 409, 'ALREADY_EXISTS');
    this.docs.set(path, { data: structuredClone(data), v: ++this.v });
    return this.get(path);
  }
  async update(path: string, flat: Record<string, unknown>, pre?: { updateTime?: string }) {
    const d = this.docs.get(path);
    if (pre?.updateTime && (!d || String(d.v) !== pre.updateTime)) throw new FirestoreError('precondition', 400, 'FAILED_PRECONDITION');
    const data = d ? d.data : {};
    for (const [k, val] of Object.entries(flat)) {
      const parts = k.split('.');
      let cur = data;
      for (let i = 0; i < parts.length - 1; i++) cur = cur[parts[i]] ??= {};
      cur[parts[parts.length - 1]] = structuredClone(val);
    }
    this.docs.set(path, { data, v: ++this.v });
    return this.get(path);
  }
  async increment(path: string, inc: Record<string, number>, set: Record<string, unknown> = {}) {
    const d = this.docs.get(path)!;
    this.merge(d.data, nestDotted(set));
    for (const [k, n] of Object.entries(inc)) {
      const parts = k.split('.');
      let cur = d.data;
      for (let i = 0; i < parts.length - 1; i++) cur = cur[parts[i]] ??= {};
      cur[parts[parts.length - 1]] = (cur[parts[parts.length - 1]] ?? 0) + n;
    }
    d.v = ++this.v;
  }
  async query(parent: string, coll: string, filters: Array<{ field: string; op: string; value: any }>) {
    const prefix = parent ? `${parent}/${coll}/` : `${coll}/`;
    const out = [];
    for (const [path] of this.docs) {
      if (!path.startsWith(prefix) || path.slice(prefix.length).includes('/')) continue;
      const doc = (await this.get(path))!;
      const ok = filters.every(f => {
        const v = f.field.split('.').reduce((o: any, k) => o?.[k], doc.data);
        if (f.op === 'EQUAL') return v === f.value;
        if (f.op === 'GREATER_THAN_OR_EQUAL') return v instanceof Date && v.getTime() >= f.value.getTime();
        return true;
      });
      if (ok) out.push(doc);
    }
    return out;
  }
}

class FakeNear {
  accounts = new Map<string, bigint>();
  proposals = new Map<string, any[]>();
  calls: string[] = [];
  async viewAccount(id: string) {
    const amt = this.accounts.get(id);
    return amt === undefined ? null : { amount: amt.toString(), locked: '0', storage_usage: 1000 };
  }
  async viewFunction(contract: string, method: string, args: any) {
    if (method === 'get_proposal') return this.proposals.get(contract)![args.id];
    if (method === 'get_last_proposal_id') return this.proposals.get(contract)?.length ?? 0;
    if (method === 'get_policy') return { roles: [] };
    return null;
  }
  async sendTransaction(signer: { accountId: string }, receiver: string, actions: any[]) {
    let value: unknown;
    for (const a of actions) {
      if (a.type === 'functionCall') {
        const args = JSON.parse(new TextDecoder().decode(a.args));
        this.calls.push(`${signer.accountId}->${receiver}.${a.methodName}`);
        if (a.methodName === 'create') { this.accounts.set(`${args.name}.${receiver}`, 6n * 10n ** 24n); this.proposals.set(`${args.name}.${receiver}`, []); }
        if (a.methodName === 'add_proposal') {
          const list = this.proposals.get(receiver)!;
          list.push({ id: list.length, status: 'InProgress', kind: args.proposal.kind, proposer: signer.accountId });
          value = list.length - 1;
        }
        if (a.methodName === 'act_proposal') {
          const p = this.proposals.get(receiver)![args.id];
          expect(args.proposal).toEqual(p.kind);
          p.status = 'Approved';
          const amt = BigInt(p.kind.Transfer.amount);
          this.accounts.set(receiver, this.accounts.get(receiver)! - amt);
        }
      } else if (a.type === 'transfer') {
        this.calls.push(`${signer.accountId}->${receiver}.transfer`);
        this.accounts.set(receiver, (this.accounts.get(receiver) ?? 0n) + a.deposit);
      } else this.calls.push(`${signer.accountId}->${receiver}.${a.type}`);
    }
    return { hash: `tx${this.calls.length}`, value, raw: {} };
  }
}

class FakePaystack {
  isTestMode = true;
  transfers: any[] = [];
  async resolveAccount(acct: string) { return { account_number: acct, account_name: 'NKECHI OKAFOR' }; }
  async createRecipient() { return { recipient_code: 'RCP_test' }; }
  async initiateTransfer(amount: number, recipient: string, reference: string) {
    this.transfers.push({ amount, recipient, reference });
    return { status: 'success', transfer_code: 'TRF_1', reference };
  }
  async listBanks() { return [{ name: 'Test Bank', code: '001', active: true, type: 'nuban' }]; }
}

// ---------- harness ----------
let app: App, fs: FakeFs, near: FakeNear, paystack: FakePaystack, pending: Promise<unknown>[];
const ctx = { waitUntil: (p: Promise<unknown>) => { pending.push(p); } };
const flush = async () => { while (pending.length) await pending.shift(); };
const chidi = { uid: 'chidi', name: 'Chidi' }, ada = { uid: 'ada', name: 'Ada' }, mama = { uid: 'mama', name: 'Mama' };

beforeEach(() => {
  const op = generateKeyPair(), gd = generateKeyPair();
  const env: Env = {
    FIREBASE_SERVICE_ACCOUNT: JSON.stringify({ project_id: 'demo', client_email: 'x@y', private_key: 'unused' }),
    PAYSTACK_SECRET_KEY: 'sk_test_x', NEAR_NETWORK: 'testnet', NEAR_RPC_URL: 'http://rpc', SPUTNIK_FACTORY: 'sputnikv2.testnet',
    OPERATOR_ACCOUNT_ID: 'operator.testnet', OPERATOR_PRIVATE_KEY: op.secretKey,
    GUARDIAN_ACCOUNT_ID: 'guardian.testnet', GUARDIAN_PRIVATE_KEY: gd.secretKey,
    DAO_CREATE_DEPOSIT_NEAR: '6', PROPOSAL_BOND_NEAR: '0.1', NGN_PER_USD: '1500', NEAR_USD_FALLBACK: '3', TESTNET_TOPUP_MAX_USD: '50',
  };
  app = new App(env);
  fs = new FakeFs(); near = new FakeNear(); paystack = new FakePaystack(); pending = [];
  Object.assign(app, { fs, near, paystack, oneclick: { tokens: async () => [] } });
});

async function setupFamily() {
  const { familyId, inviteCode } = await h.createFamily(app, chidi, { name: 'Okonkwo Family' }, ctx) as any;
  await flush();
  await h.joinFamily(app, ada, { inviteCode, role: 'sibling' }, ctx);
  await h.joinFamily(app, mama, { inviteCode, role: 'parent' }, ctx);
  return familyId as string;
}

describe('full family flow', () => {
  it('creates the DAO, funds it, approves a shop and pays it through the guardian', async () => {
    const familyId = await setupFamily();
    const fam = (await fs.get(`families/${familyId}`))!.data;
    expect(fam.dao.status).toBe('active');
    expect(fam.siblingUids).toEqual(['chidi', 'ada']);
    expect(fam.parentUids).toEqual(['mama']);
    expect(near.calls).toContain('operator.testnet->sputnikv2.testnet.create');
    expect(near.calls).toContain('guardian.testnet->guardian.testnet.addKey');
    expect((await fs.get(`_secrets/${familyId}`))!.data.guardianKey).toMatch(/^ed25519:/);

    // Fund with a testnet top-up: $50 => ₦75,000 and NEAR lands in the DAO.
    const top = await h.fundTestnet(app, chidi, { familyId, amountUsd: 50 }, ctx) as any;
    expect(top.status).toBe('credited');
    await h.fundTestnet(app, ada, { familyId, amountUsd: 50 }, ctx);
    expect((await fs.get(`families/${familyId}`))!.data.balanceNgn).toBe(150_000);

    // Mama adds her shop: pending until 2 siblings approve.
    const m = await h.addMerchant(app, mama, { familyId, displayName: 'Mama Nkechi Stores', category: 'food', bankCode: '001', accountNumber: '0123456789' }, ctx) as any;
    expect(m.status).toBe('pending');
    expect(m.nameMatch).toBe(1);
    // Payment to a pending shop is blocked (stolen phone case).
    const blocked = await h.requestPayment(app, mama, { familyId, merchantId: m.merchantId, amountNgn: 40_000 }, ctx) as any;
    expect(blocked.outcome).toBe('blocked');
    await h.voteMerchant(app, chidi, { familyId, merchantId: m.merchantId, approve: true }, ctx);
    const v = await h.voteMerchant(app, ada, { familyId, merchantId: m.merchantId, approve: true }, ctx) as any;
    expect(v.status).toBe('approved');

    // Normal payment goes through: proposal, guardian vote, Paystack transfer.
    const pay = await h.requestPayment(app, mama, { familyId, merchantId: m.merchantId, amountNgn: 45_000, note: 'Groceries' }, ctx) as any;
    expect(pay.outcome).toBe('approved');
    await flush();
    const p = (await fs.get(`families/${familyId}/payments/${pay.paymentId}`))!.data;
    expect(p.status).toBe('paid');
    expect(p.onchain.status).toBe('Approved');
    expect(p.onchain.approvedBy).toBe('guardian');
    expect(near.calls).toContain(`guardian.testnet->${fam.dao.id}.act_proposal`);
    expect(paystack.transfers[0]).toMatchObject({ amount: 4_500_000, recipient: 'RCP_test', reference: `pm-${familyId}-${pay.paymentId}` });
    const after = (await fs.get(`families/${familyId}`))!.data;
    expect(after.balanceNgn).toBe(105_000);
    expect(after.purposes.food.spentNgn).toBe(45_000);
  });

  it('escalates large payments and executes them after sibling votes', async () => {
    const familyId = await setupFamily();
    await h.fundTestnet(app, chidi, { familyId, amountUsd: 50 }, ctx);
    await h.fundTestnet(app, ada, { familyId, amountUsd: 50 }, ctx);
    const m = await h.addMerchant(app, chidi, { familyId, displayName: 'Nkechi', category: 'school', bankCode: '001', accountNumber: '0123456780' }, ctx) as any;
    await h.voteMerchant(app, ada, { familyId, merchantId: m.merchantId, approve: true }, ctx);
    const pay = await h.requestPayment(app, mama, { familyId, merchantId: m.merchantId, amountNgn: 110_000 }, ctx) as any;
    expect(pay.outcome).toBe('escalated');
    await flush();
    expect((await fs.get(`families/${familyId}/payments/${pay.paymentId}`))!.data.status).toBe('escalated');
    await h.votePayment(app, chidi, { familyId, paymentId: pay.paymentId, approve: true }, ctx);
    await h.votePayment(app, ada, { familyId, paymentId: pay.paymentId, approve: true }, ctx);
    await flush();
    const p = (await fs.get(`families/${familyId}/payments/${pay.paymentId}`))!.data;
    expect(p.status).toBe('paid');
    expect(p.onchain.approvedBy).toBe('family council');
  });

  it('applies budget changes only after enough sibling votes, and parents cannot vote', async () => {
    const familyId = await setupFamily();
    const c = await h.proposeChange(app, chidi, { familyId, type: 'budgets', payload: { purposes: { food: { label: 'Food', budgetNgn: 200_000 } } } }, ctx) as any;
    expect(c.status).toBe('pending');
    await expect(h.voteChange(app, mama, { familyId, changeId: c.changeId, approve: true }, ctx)).rejects.toThrow(/Only siblings/);
    await h.voteChange(app, ada, { familyId, changeId: c.changeId, approve: true }, ctx);
    const fam = (await fs.get(`families/${familyId}`))!.data;
    expect(Object.keys(fam.purposes)).toEqual(['food']);
    expect(fam.purposes.food.budgetNgn).toBe(200_000);
  });

  it('rejects outsiders', async () => {
    const familyId = await setupFamily();
    await expect(h.requestPayment(app, { uid: 'stranger' }, { familyId, merchantId: 'x', amountNgn: 100 }, ctx)).rejects.toThrow(/not part of this family/);
  });
});
