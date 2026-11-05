// Minimal NEAR client: borsh transaction encoding, ed25519 signing and JSON-RPC.
// Kept dependency-light so it fits comfortably in a free Cloudflare Worker.
// Serialization is verified byte-for-byte against near-api-js in test/near.test.ts.
import { ed25519 } from '@noble/curves/ed25519.js';
import { sha256 } from '@noble/hashes/sha2.js';
import bs58 from 'bs58';

export const YOCTO_PER_NEAR = 10n ** 24n;
export const TGAS = 10n ** 12n;

// ---------- borsh ----------
export class BorshWriter {
  private buf: number[] = [];
  u8(v: number) { this.buf.push(v & 0xff); return this; }
  u32(v: number) { for (let i = 0; i < 4; i++) this.buf.push((v >>> (8 * i)) & 0xff); return this; }
  u64(v: bigint) { return this.uint(v, 8); }
  u128(v: bigint) { return this.uint(v, 16); }
  private uint(v: bigint, bytes: number) {
    if (v < 0n) throw new Error('negative integer');
    for (let i = 0; i < bytes; i++) this.buf.push(Number((v >> BigInt(8 * i)) & 0xffn));
    if (v >> BigInt(8 * bytes) !== 0n) throw new Error('integer overflow');
    return this;
  }
  fixed(b: Uint8Array) { for (const x of b) this.buf.push(x); return this; }
  bytes(b: Uint8Array) { this.u32(b.length); return this.fixed(b); }
  string(s: string) { return this.bytes(new TextEncoder().encode(s)); }
  toBytes() { return Uint8Array.from(this.buf); }
}

// ---------- keys ----------
export function parseSecretKey(secret: string): Uint8Array {
  const raw = secret.startsWith('ed25519:') ? secret.slice(8) : secret;
  const bytes = bs58.decode(raw);
  if (bytes.length !== 64 && bytes.length !== 32) throw new Error('Invalid ed25519 secret key length');
  return bytes.slice(0, 32); // seed
}

export function publicKeyToString(pk: Uint8Array) { return 'ed25519:' + bs58.encode(pk); }

export function publicKeyFromString(s: string): Uint8Array {
  const raw = s.startsWith('ed25519:') ? s.slice(8) : s;
  const b = bs58.decode(raw);
  if (b.length !== 32) throw new Error('Invalid ed25519 public key');
  return b;
}

export function generateKeyPair(): { secretKey: string; publicKey: string } {
  const seed = ed25519.utils.randomSecretKey();
  const pub = ed25519.getPublicKey(seed);
  const full = new Uint8Array(64); full.set(seed, 0); full.set(pub, 32);
  return { secretKey: 'ed25519:' + bs58.encode(full), publicKey: publicKeyToString(pub) };
}

export class Signer {
  readonly seed: Uint8Array;
  readonly publicKey: Uint8Array;
  constructor(readonly accountId: string, secretKey: string) {
    this.seed = parseSecretKey(secretKey);
    this.publicKey = ed25519.getPublicKey(this.seed);
  }
  get publicKeyString() { return publicKeyToString(this.publicKey); }
  sign(msg: Uint8Array) { return ed25519.sign(msg, this.seed); }
}

// ---------- actions & transactions ----------
export type AccessKeyPermission =
  | { type: 'fullAccess' }
  | { type: 'functionCall'; allowance: bigint | null; receiverId: string; methodNames: string[] };

export type Action =
  | { type: 'functionCall'; methodName: string; args: Uint8Array; gas: bigint; deposit: bigint }
  | { type: 'transfer'; deposit: bigint }
  | { type: 'addKey'; publicKey: Uint8Array; permission: AccessKeyPermission };

export const functionCall = (methodName: string, args: unknown, gas: bigint, deposit = 0n): Action => ({
  type: 'functionCall', methodName, args: new TextEncoder().encode(JSON.stringify(args)), gas, deposit,
});
export const transfer = (deposit: bigint): Action => ({ type: 'transfer', deposit });
export const addFunctionCallKey = (publicKey: Uint8Array, receiverId: string, methodNames: string[], allowance: bigint | null): Action => ({
  type: 'addKey', publicKey, permission: { type: 'functionCall', allowance, receiverId, methodNames },
});

export interface TransactionFields {
  signerId: string; publicKey: Uint8Array; nonce: bigint; receiverId: string; blockHash: Uint8Array; actions: Action[];
}

function writePublicKey(w: BorshWriter, pk: Uint8Array) { w.u8(0); w.fixed(pk); }

function writeAction(w: BorshWriter, a: Action) {
  switch (a.type) {
    case 'functionCall':
      w.u8(2); w.string(a.methodName); w.bytes(a.args); w.u64(a.gas); w.u128(a.deposit); return;
    case 'transfer':
      w.u8(3); w.u128(a.deposit); return;
    case 'addKey':
      w.u8(5); writePublicKey(w, a.publicKey);
      w.u64(0n); // access key nonce
      if (a.permission.type === 'fullAccess') { w.u8(1); return; }
      w.u8(0);
      if (a.permission.allowance === null) w.u8(0); else { w.u8(1); w.u128(a.permission.allowance); }
      w.string(a.permission.receiverId);
      w.u32(a.permission.methodNames.length);
      for (const m of a.permission.methodNames) w.string(m);
      return;
  }
}

export function serializeTransaction(t: TransactionFields): Uint8Array {
  if (t.blockHash.length !== 32) throw new Error('blockHash must be 32 bytes');
  const w = new BorshWriter();
  w.string(t.signerId);
  writePublicKey(w, t.publicKey);
  w.u64(t.nonce);
  w.string(t.receiverId);
  w.fixed(t.blockHash);
  w.u32(t.actions.length);
  for (const a of t.actions) writeAction(w, a);
  return w.toBytes();
}

export function signTransaction(t: TransactionFields, signer: Signer): { signed: Uint8Array; hash: Uint8Array } {
  const txBytes = serializeTransaction(t);
  const hash = sha256(txBytes);
  const sig = signer.sign(hash);
  const w = new BorshWriter();
  w.fixed(txBytes); w.u8(0); w.fixed(sig);
  return { signed: w.toBytes(), hash };
}

// ---------- base64 helpers (no Buffer in Workers) ----------
export function toBase64(bytes: Uint8Array): string {
  let s = '';
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(s);
}
export function fromBase64(b64: string): Uint8Array {
  const s = atob(b64);
  const out = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
  return out;
}

// ---------- amounts ----------
export function nearToYocto(near: string | number): bigint {
  const s = typeof near === 'number' ? near.toFixed(24) : near.trim();
  if (!/^\d+(\.\d+)?$/.test(s)) throw new Error(`Invalid NEAR amount: ${near}`);
  const [whole, frac = ''] = s.split('.');
  return BigInt(whole) * YOCTO_PER_NEAR + BigInt((frac + '0'.repeat(24)).slice(0, 24));
}
export function yoctoToNear(yocto: bigint | string, decimals = 4): number {
  const y = typeof yocto === 'string' ? BigInt(yocto) : yocto;
  const scale = 10n ** BigInt(24 - decimals);
  return Number(y / scale) / 10 ** decimals;
}

// ---------- RPC ----------
export class NearRpcError extends Error {
  constructor(message: string, readonly data?: unknown) { super(message); }
}

export interface TxResult { hash: string; value: unknown; raw: any }

export class NearClient {
  // FIX: wrap global fetch so it is never invoked with `this` = the NearClient instance
  // (a bare stored `fetch` throws "Illegal invocation" in Cloudflare Workers).
  constructor(
    readonly rpcUrl: string,
    private fetchImpl: typeof fetch = (input, init) => fetch(input, init),
  ) {}

  async rpc<T = any>(method: string, params: unknown): Promise<T> {
    const res = await this.fetchImpl(this.rpcUrl, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ jsonrpc: '2.0', id: 'pm', method, params }),
    });
    const text = await res.text();
    let json: any;
    try { json = JSON.parse(text); } catch { throw new NearRpcError(`RPC ${method} returned non-JSON (${res.status})`, text.slice(0, 300)); }
    if (json.error) {
      const e = json.error;
      const detail = e.cause?.name ?? e.name ?? 'RPC_ERROR';
      throw new NearRpcError(`${detail}: ${JSON.stringify(e.data ?? e.cause?.info ?? e.message)}`, e);
    }
    if (json.result?.error) throw new NearRpcError(String(json.result.error), json.result);
    return json.result as T;
  }

  async viewAccount(accountId: string): Promise<{ amount: string; locked: string; storage_usage: number } | null> {
    try {
      return await this.rpc('query', { request_type: 'view_account', finality: 'final', account_id: accountId });
    } catch (e) {
      if (e instanceof NearRpcError && /UNKNOWN_ACCOUNT|does not exist/i.test(e.message)) return null;
      throw e;
    }
  }

  async viewFunction<T = any>(contractId: string, methodName: string, args: unknown = {}): Promise<T> {
    const r = await this.rpc<{ result: number[] }>('query', {
      request_type: 'call_function', finality: 'final', account_id: contractId, method_name: methodName,
      args_base64: toBase64(new TextEncoder().encode(JSON.stringify(args))),
    });
    const text = new TextDecoder().decode(Uint8Array.from(r.result));
    return (text ? JSON.parse(text) : null) as T;
  }

  async accessKey(accountId: string, publicKey: string): Promise<{ nonce: number | string; block_hash: string }> {
    return this.rpc('query', { request_type: 'view_access_key', finality: 'final', account_id: accountId, public_key: publicKey });
  }

  async sendTransaction(signer: Signer, receiverId: string, actions: Action[], attempts = 3): Promise<TxResult> {
    let lastErr: unknown;
    for (let attempt = 0; attempt < attempts; attempt++) {
      const ak = await this.accessKey(signer.accountId, signer.publicKeyString);
      const fields: TransactionFields = {
        signerId: signer.accountId, publicKey: signer.publicKey,
        nonce: BigInt(ak.nonce) + 1n + BigInt(attempt), receiverId,
        blockHash: bs58.decode(ak.block_hash), actions,
      };
      const { signed, hash } = signTransaction(fields, signer);
      const b64 = toBase64(signed);
      try {
        let raw: any;
        try {
          raw = await this.rpc('send_tx', { signed_tx_base64: b64, wait_until: 'EXECUTED_OPTIMISTIC' });
        } catch (e) {
          if (e instanceof NearRpcError && /METHOD_NOT_FOUND|Method not found/i.test(e.message)) {
            raw = await this.rpc('broadcast_tx_commit', [b64]);
          } else throw e;
        }
        return parseOutcome(bs58.encode(hash), raw);
      } catch (e) {
        lastErr = e;
        if (e instanceof NearRpcError && /InvalidNonce|Expired|TIMEOUT/i.test(e.message)) continue;
        throw e;
      }
    }
    throw lastErr;
  }
}

export function parseOutcome(hash: string, raw: any): TxResult {
  const status = raw?.status ?? {};
  if (status.Failure) throw new NearRpcError(`Transaction ${hash} failed: ${JSON.stringify(status.Failure)}`, raw);
  for (const r of raw?.receipts_outcome ?? []) {
    const f = r?.outcome?.status?.Failure;
    if (f) throw new NearRpcError(`Receipt in ${hash} failed: ${JSON.stringify(f)}`, raw);
  }
  let value: unknown = undefined;
  if (typeof status.SuccessValue === 'string' && status.SuccessValue.length) {
    const text = new TextDecoder().decode(fromBase64(status.SuccessValue));
    try { value = JSON.parse(text); } catch { value = text; }
  }
  return { hash, value, raw };
}

export function explorerTxUrl(network: string, hash: string) {
  return network === 'mainnet' ? `https://nearblocks.io/txns/${hash}` : `https://testnet.nearblocks.io/txns/${hash}`;
}
export function explorerAccountUrl(network: string, account: string) {
  return network === 'mainnet' ? `https://nearblocks.io/address/${account}` : `https://testnet.nearblocks.io/address/${account}`;
}