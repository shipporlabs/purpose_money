// Paystack: bank list, account verification, transfer recipients and transfers.
export class PaystackError extends Error {
  constructor(message: string, readonly status: number) { super(message); }
}

export class Paystack {
  // FIX: wrap global fetch so it is never invoked with `this` = the Paystack instance
  // (a bare stored `fetch` throws "Illegal invocation" in Cloudflare Workers).
  constructor(
    private readonly secretKey: string,
    private readonly fetchImpl: typeof fetch = (input, init) => fetch(input, init),
  ) {}

  get isTestMode() { return this.secretKey.startsWith('sk_test_'); }

  private async call<T = any>(method: string, path: string, body?: unknown): Promise<T> {
    const res = await this.fetchImpl(`https://api.paystack.co${path}`, {
      method,
      headers: { authorization: `Bearer ${this.secretKey}`, 'content-type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    let json: any = {};
    try { json = await res.json(); } catch { /* empty body */ }
    if (!res.ok || json.status === false) {
      throw new PaystackError(json?.message ?? `Paystack error ${res.status}`, res.status);
    }
    return json.data as T;
  }

  listBanks() {
    return this.call<Array<{ name: string; code: string; active: boolean; type: string }>>('GET', '/bank?currency=NGN&perPage=200');
  }

  resolveAccount(accountNumber: string, bankCode: string) {
    const qs = new URLSearchParams({ account_number: accountNumber, bank_code: bankCode });
    return this.call<{ account_number: string; account_name: string }>('GET', `/bank/resolve?${qs}`);
  }

  createRecipient(name: string, accountNumber: string, bankCode: string) {
    return this.call<{ recipient_code: string }>('POST', '/transferrecipient', {
      type: 'nuban', name, account_number: accountNumber, bank_code: bankCode, currency: 'NGN',
    });
  }

  initiateTransfer(amountKobo: number, recipientCode: string, reference: string, reason: string) {
    return this.call<{ status: string; transfer_code: string; reference: string }>('POST', '/transfer', {
      source: 'balance', amount: amountKobo, recipient: recipientCode, reference, reason: reason.slice(0, 100),
    });
  }

  verifyTransfer(reference: string) {
    return this.call<{ status: string; transfer_code: string }>('GET', `/transfer/verify/${encodeURIComponent(reference)}`);
  }
}

/** Verify Paystack's x-paystack-signature (HMAC SHA-512 of the raw body with the secret key). */
export async function verifyPaystackSignature(secretKey: string, rawBody: string, signature: string | null): Promise<boolean> {
  if (!signature) return false;
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secretKey), { name: 'HMAC', hash: 'SHA-512' }, false, ['sign']);
  const mac = new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(rawBody)));
  const hex = Array.from(mac, b => b.toString(16).padStart(2, '0')).join('');
  if (hex.length !== signature.length) return false;
  let diff = 0;
  for (let i = 0; i < hex.length; i++) diff |= hex.charCodeAt(i) ^ signature.charCodeAt(i);
  return diff === 0;
}

/** Paystack reference: lowercase, 16–50 chars, [a-z0-9_-]. Ids are generated lowercase so this round-trips. */
export function paymentReference(familyId: string, paymentId: string) { return `pm-${familyId}-${paymentId}`; }
export function parseReference(ref: string): { familyId: string; paymentId: string } | null {
  const m = /^pm-([a-z0-9]+)-([a-z0-9]+)$/.exec(ref);
  return m ? { familyId: m[1], paymentId: m[2] } : null;
}