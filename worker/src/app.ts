// Shared services, config and helpers for the Worker.
import { Firestore, FirestoreError, ServiceAccount, Doc } from './firestore';
import { NearClient, Signer, nearToYocto } from './near';
import { Paystack } from './paystack';
import { OneClick, OneClickToken } from './oneclick';

export interface Env {
  FIREBASE_SERVICE_ACCOUNT: string;
  PAYSTACK_SECRET_KEY: string;
  NEAR_NETWORK: string;
  NEAR_RPC_URL: string;
  SPUTNIK_FACTORY: string;
  OPERATOR_ACCOUNT_ID: string;
  OPERATOR_PRIVATE_KEY: string;
  GUARDIAN_ACCOUNT_ID: string;
  GUARDIAN_PRIVATE_KEY: string;
  TREASURY_ACCOUNT_ID?: string;
  DAO_CREATE_DEPOSIT_NEAR: string;
  PROPOSAL_BOND_NEAR: string;
  NGN_PER_USD: string;
  NEAR_USD_FALLBACK: string;
  TESTNET_TOPUP_MAX_USD: string;
  ONECLICK_API_KEY?: string;
  INTENTS_RECIPIENT?: string;
  AI_BASE_URL?: string;
  AI_API_KEY?: string;
  AI_MODEL?: string;
  ALLOWED_ORIGIN?: string;
}

export class HttpError extends Error {
  constructor(readonly status: number, message: string) { super(message); }
}

export function required(env: Env, key: keyof Env): string {
  const v = env[key];
  if (!v) throw new HttpError(500, `Worker is missing the ${key} setting. See README → Cloudflare Worker.`);
  return v;
}

let tokenCache: { at: number; tokens: OneClickToken[] } | null = null;
let banksCache: { at: number; banks: Array<{ name: string; code: string }> } | null = null;

export class App {
  readonly fs: Firestore;
  readonly near: NearClient;
  readonly paystack: Paystack;
  readonly oneclick: OneClick;
  readonly network: string;

  constructor(readonly env: Env) {
    let sa: ServiceAccount;
    try { sa = JSON.parse(required(env, 'FIREBASE_SERVICE_ACCOUNT')); }
    catch (e) { if (e instanceof HttpError) throw e; throw new HttpError(500, 'FIREBASE_SERVICE_ACCOUNT is not valid JSON'); }
    this.fs = new Firestore(sa);
    this.near = new NearClient(env.NEAR_RPC_URL || 'https://test.rpc.fastnear.com');
    this.paystack = new Paystack(required(env, 'PAYSTACK_SECRET_KEY'));
    this.oneclick = new OneClick(env.ONECLICK_API_KEY);
    this.network = env.NEAR_NETWORK || 'testnet';
  }

  get projectId(): string { return JSON.parse(this.env.FIREBASE_SERVICE_ACCOUNT).project_id; }
  get factory() { return this.env.SPUTNIK_FACTORY || (this.network === 'mainnet' ? 'sputnik-dao.near' : 'sputnikv2.testnet'); }
  operator() { return new Signer(required(this.env, 'OPERATOR_ACCOUNT_ID'), required(this.env, 'OPERATOR_PRIVATE_KEY')); }
  guardianFullAccess() { return new Signer(required(this.env, 'GUARDIAN_ACCOUNT_ID'), required(this.env, 'GUARDIAN_PRIVATE_KEY')); }
  get treasury() { return this.env.TREASURY_ACCOUNT_ID || required(this.env, 'OPERATOR_ACCOUNT_ID'); }
  get ngnPerUsd() { return Number(this.env.NGN_PER_USD || '1500'); }
  get bondYocto() { return nearToYocto(this.env.PROPOSAL_BOND_NEAR || '0.1'); }

  async tokens(): Promise<OneClickToken[]> {
    if (tokenCache && Date.now() - tokenCache.at < 5 * 60_000) return tokenCache.tokens;
    const tokens = await this.oneclick.tokens();
    tokenCache = { at: Date.now(), tokens };
    return tokens;
  }

  async nearUsd(): Promise<number> {
    try {
      const t = (await this.tokens()).find(x => x.blockchain === 'near' && (x.assetId === 'nep141:wrap.near' || x.symbol.toUpperCase() === 'WNEAR'));
      if (t && t.price > 0) return t.price;
    } catch { /* fall back */ }
    return Number(this.env.NEAR_USD_FALLBACK || '3');
  }

  async ngnToYocto(ngn: number): Promise<bigint> {
    const near = ngn / this.ngnPerUsd / (await this.nearUsd());
    return nearToYocto(near.toFixed(6));
  }
  async usdToYocto(usd: number): Promise<bigint> {
    return nearToYocto((usd / (await this.nearUsd())).toFixed(6));
  }

  async banks() {
    if (banksCache && Date.now() - banksCache.at < 6 * 3_600_000) return banksCache.banks;
    const all = await this.paystack.listBanks();
    const banks = all.filter(b => b.active !== false && (!b.type || b.type === 'nuban'))
      .map(b => ({ name: b.name, code: b.code }))
      .sort((a, b) => a.name.localeCompare(b.name));
    banksCache = { at: Date.now(), banks };
    return banks;
  }

  /** Read-modify-write with an optimistic precondition, retried on conflicts. */
  async mutate<T extends Record<string, any>>(path: string, fn: (data: T) => Record<string, unknown> | null): Promise<T> {
    for (let i = 0; i < 4; i++) {
      const doc = await this.fs.get<T>(path);
      if (!doc) throw new HttpError(404, 'Not found');
      const patch = fn(doc.data);
      if (!patch) return doc.data;
      try {
        await this.fs.update(path, patch, { updateTime: doc.updateTime });
        return { ...doc.data, ...patch } as T;
      } catch (e) {
        if (e instanceof FirestoreError && e.isConflict) continue;
        throw e;
      }
    }
    throw new HttpError(409, 'Someone else changed this at the same moment. Please try again.');
  }
}

export interface Family {
  name: string; createdBy: string; siblingUids: string[]; parentUids: string[]; memberUids: string[];
  memberNames: Record<string, string>; inviteCode: string;
  purposes: Record<string, { label: string; budgetNgn: number; spentNgn: number }>;
  rules: import('./guardian').Rules; balanceNgn: number; contributedNgn?: Record<string, number>;
  network: string; dao: { id: string; status: 'creating' | 'active' | 'failed'; createTx?: string; error?: string; guardianKey?: string };
}

export async function loadFamily(app: App, familyId: string, uid: string, opts: { sibling?: boolean } = {}): Promise<Doc<Family>> {
  if (!/^[a-z0-9]{6,40}$/.test(familyId ?? '')) throw new HttpError(400, 'Invalid familyId');
  const fam = await app.fs.get<Family>(`families/${familyId}`);
  if (!fam) throw new HttpError(404, 'Family not found');
  if (!fam.data.memberUids?.includes(uid)) throw new HttpError(403, 'You are not part of this family');
  if (opts.sibling && !fam.data.siblingUids.includes(uid)) throw new HttpError(403, 'Only siblings can do this');
  return fam;
}
