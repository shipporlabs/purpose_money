// Firestore REST client authenticated with a service account (works on the free Spark plan).
import { SignJWT, importPKCS8 } from 'jose';

export interface ServiceAccount { project_id: string; client_email: string; private_key: string }

type FsValue = Record<string, unknown>;

export class Timestamp {
  constructor(readonly date: Date) {}
}

export function encodeValue(v: unknown): FsValue {
  if (v === null || v === undefined) return { nullValue: null };
  if (v instanceof Date) return { timestampValue: v.toISOString() };
  if (v instanceof Timestamp) return { timestampValue: v.date.toISOString() };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  if (typeof v === 'bigint') return { integerValue: v.toString() };
  if (typeof v === 'string') return { stringValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(encodeValue) } };
  if (typeof v === 'object') return { mapValue: { fields: encodeFields(v as Record<string, unknown>) } };
  throw new Error(`Cannot encode ${typeof v}`);
}

export function encodeFields(obj: Record<string, unknown>): Record<string, FsValue> {
  const out: Record<string, FsValue> = {};
  for (const [k, v] of Object.entries(obj)) if (v !== undefined) out[k] = encodeValue(v);
  return out;
}

export function decodeValue(v: any): unknown {
  if (!v || 'nullValue' in v) return null;
  if ('booleanValue' in v) return v.booleanValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return v.doubleValue;
  if ('stringValue' in v) return v.stringValue;
  if ('timestampValue' in v) return new Date(v.timestampValue);
  if ('arrayValue' in v) return (v.arrayValue.values ?? []).map(decodeValue);
  if ('mapValue' in v) return decodeFields(v.mapValue.fields ?? {});
  if ('referenceValue' in v) return v.referenceValue;
  return null;
}

export function decodeFields(fields: Record<string, any>): Record<string, any> {
  const out: Record<string, any> = {};
  for (const [k, v] of Object.entries(fields)) out[k] = decodeValue(v);
  return out;
}

/** Turn {"a.b": 1, "c": 2} into nested {a:{b:1}, c:2} for a PATCH body. */
export function nestDotted(flat: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, any> = {};
  for (const [path, v] of Object.entries(flat)) {
    const parts = path.split('.');
    let cur = out;
    for (let i = 0; i < parts.length - 1; i++) cur = cur[parts[i]] ??= {};
    cur[parts[parts.length - 1]] = v;
  }
  return out;
}

/** Quote field-path segments that aren't plain identifiers (e.g. uids starting with a digit). */
export function quoteFieldPath(path: string): string {
  return path.split('.').map(seg => /^[a-zA-Z_][a-zA-Z_0-9]*$/.test(seg) ? seg : '`' + seg.replace(/[`\\]/g, m => '\\' + m) + '`').join('.');
}

export interface Doc<T = Record<string, any>> { id: string; path: string; data: T; updateTime: string }

export class FirestoreError extends Error {
  constructor(message: string, readonly status: number, readonly code?: string) { super(message); }
  get isConflict() { return this.code === 'FAILED_PRECONDITION' || this.code === 'ABORTED' || this.status === 409; }
}

export interface Filter { field: string; op: 'EQUAL' | 'GREATER_THAN_OR_EQUAL' | 'LESS_THAN' | 'ARRAY_CONTAINS' | 'IN'; value: unknown }

let cachedToken: { token: string; exp: number; email: string } | null = null;

export class Firestore {
  private readonly root: string;
  // FIX: wrap global fetch so it is never invoked with `this` = the Firestore instance
  // (a bare stored `fetch` throws "Illegal invocation" in Cloudflare Workers).
  constructor(
    private readonly sa: ServiceAccount,
    private readonly fetchImpl: typeof fetch = (input, init) => fetch(input, init),
  ) {
    this.root = `projects/${sa.project_id}/databases/(default)/documents`;
  }

  private async token(): Promise<string> {
    const now = Math.floor(Date.now() / 1000);
    if (cachedToken && cachedToken.email === this.sa.client_email && cachedToken.exp - 60 > now) return cachedToken.token;
    const key = await importPKCS8(this.sa.private_key, 'RS256');
    const assertion = await new SignJWT({ scope: 'https://www.googleapis.com/auth/datastore' })
      .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
      .setIssuer(this.sa.client_email).setSubject(this.sa.client_email)
      .setAudience('https://oauth2.googleapis.com/token')
      .setIssuedAt(now).setExpirationTime(now + 3600).sign(key);
    const res = await this.fetchImpl('https://oauth2.googleapis.com/token', {
      method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }),
    });
    const json: any = await res.json();
    if (!res.ok) throw new FirestoreError(`Google auth failed: ${JSON.stringify(json)}`, res.status);
    cachedToken = { token: json.access_token, exp: now + (json.expires_in ?? 3600), email: this.sa.client_email };
    return cachedToken.token;
  }

  private async call(method: string, url: string, body?: unknown): Promise<any> {
    const res = await this.fetchImpl(url, {
      method,
      headers: { authorization: `Bearer ${await this.token()}`, 'content-type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await res.text();
    const json = text ? JSON.parse(text) : {};
    if (!res.ok) {
      const err = Array.isArray(json) ? json[0]?.error : json?.error;
      throw new FirestoreError(err?.message ?? `Firestore ${res.status}`, res.status, err?.status);
    }
    return json;
  }

  private url(path: string) { return `https://firestore.googleapis.com/v1/${this.root}/${path}`; }

  private toDoc(raw: any): Doc {
    const name: string = raw.name;
    const rel = name.split('/documents/')[1];
    return { id: rel.split('/').pop()!, path: rel, data: decodeFields(raw.fields ?? {}), updateTime: raw.updateTime };
  }

  async get<T = Record<string, any>>(path: string): Promise<Doc<T> | null> {
    try { return this.toDoc(await this.call('GET', this.url(path))) as Doc<T>; }
    catch (e) { if (e instanceof FirestoreError && e.status === 404) return null; throw e; }
  }

  /** Create a document; fails if it already exists. */
  async create(path: string, data: Record<string, unknown>): Promise<Doc> {
    const idx = path.lastIndexOf('/');
    const parent = path.slice(0, idx), id = path.slice(idx + 1);
    const raw = await this.call('POST', `${this.url(parent)}?documentId=${encodeURIComponent(id)}`, { fields: encodeFields(data) });
    return this.toDoc(raw);
  }

  /** Update only the given (dotted) field paths. Optional optimistic-concurrency precondition. */
  async update(path: string, flat: Record<string, unknown>, precondition?: { updateTime?: string; exists?: boolean }): Promise<Doc> {
    const qs = new URLSearchParams();
    for (const k of Object.keys(flat)) qs.append('updateMask.fieldPaths', quoteFieldPath(k));
    if (precondition?.updateTime) qs.append('currentDocument.updateTime', precondition.updateTime);
    if (precondition?.exists !== undefined) qs.append('currentDocument.exists', String(precondition.exists));
    const raw = await this.call('PATCH', `${this.url(path)}?${qs}`, { fields: encodeFields(nestDotted(flat)) });
    return this.toDoc(raw);
  }

  /** Atomic numeric increments plus optional plain field updates on one document. */
  async increment(path: string, increments: Record<string, number>, set: Record<string, unknown> = {}): Promise<void> {
    const name = `${this.root}/${path}`;
    const writes: any[] = [];
    const setKeys = Object.keys(set);
    writes.push({
      update: { name, fields: encodeFields(nestDotted(set)) },
      updateMask: { fieldPaths: setKeys.map(quoteFieldPath) },
      currentDocument: { exists: true },
      updateTransforms: Object.entries(increments).map(([fieldPath, n]) => ({ fieldPath: quoteFieldPath(fieldPath), increment: encodeValue(n) })),
    });
    await this.call('POST', `https://firestore.googleapis.com/v1/projects/${this.sa.project_id}/databases/(default)/documents:commit`, { writes });
  }

  async query(parentPath: string, collectionId: string, filters: Filter[] = [], limit = 200): Promise<Doc[]> {
    const where = filters.length === 0 ? undefined : filters.length === 1
      ? { fieldFilter: { field: { fieldPath: filters[0].field }, op: filters[0].op, value: encodeValue(filters[0].value) } }
      : { compositeFilter: { op: 'AND', filters: filters.map(f => ({ fieldFilter: { field: { fieldPath: f.field }, op: f.op, value: encodeValue(f.value) } })) } };
    const url = parentPath ? `${this.url(parentPath)}:runQuery` : `https://firestore.googleapis.com/v1/${this.root}:runQuery`;
    const rows: any[] = await this.call('POST', url, { structuredQuery: { from: [{ collectionId }], where, limit } });
    return rows.filter(r => r.document).map(r => this.toDoc(r.document));
  }
}

const ID_ALPHABET = 'abcdefghijklmnopqrstuvwxyz0123456789';
export function newId(len = 20): string {
  const bytes = crypto.getRandomValues(new Uint8Array(len));
  let s = '';
  for (const b of bytes) s += ID_ALPHABET[b % ID_ALPHABET.length];
  return s;
}
export function inviteCode(): string {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const bytes = crypto.getRandomValues(new Uint8Array(6));
  return Array.from(bytes, b => alphabet[b % alphabet.length]).join('');
}