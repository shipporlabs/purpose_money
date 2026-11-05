// NEAR Intents 1Click API: cross-chain funding quotes, deposit addresses and status.
// Docs: https://docs.near-intents.org (OpenAPI: https://1click.chaindefuser.com/docs/v0/openapi.yaml)
export interface OneClickToken {
  assetId: string; decimals: number; blockchain: string; symbol: string; price: number; contractAddress?: string;
}

export type OneClickStatus =
  | 'KNOWN_DEPOSIT_TX' | 'PENDING_DEPOSIT' | 'INCOMPLETE_DEPOSIT' | 'PROCESSING' | 'SUCCESS' | 'REFUNDED' | 'FAILED';

const BASE = 'https://1click.chaindefuser.com';

export class OneClick {
  constructor(private readonly apiKey: string | undefined, private readonly fetchImpl: typeof fetch = fetch) {}

  private headers(auth: boolean) {
    const h: Record<string, string> = { 'content-type': 'application/json' };
    if (auth && this.apiKey) h['X-API-Key'] = this.apiKey;
    return h;
  }

  async tokens(): Promise<OneClickToken[]> {
    const res = await this.fetchImpl(`${BASE}/v0/tokens`, { headers: this.headers(false) });
    if (!res.ok) throw new Error(`1Click tokens failed (${res.status})`);
    return res.json();
  }

  async quote(req: {
    originAsset: string; destinationAsset: string; amount: string; refundTo: string; recipient: string; dry: boolean;
  }) {
    if (!this.apiKey) throw new Error('ONECLICK_API_KEY is not configured on the Worker');
    const body = {
      dry: req.dry,
      swapType: 'EXACT_INPUT',
      slippageTolerance: 100,
      originAsset: req.originAsset,
      depositType: 'ORIGIN_CHAIN',
      destinationAsset: req.destinationAsset,
      amount: req.amount,
      refundTo: req.refundTo,
      refundType: 'ORIGIN_CHAIN',
      recipient: req.recipient,
      recipientType: 'DESTINATION_CHAIN',
      deadline: new Date(Date.now() + 60 * 60 * 1000).toISOString(),
      referral: 'purpose-money',
    };
    const res = await this.fetchImpl(`${BASE}/v0/quote`, { method: 'POST', headers: this.headers(true), body: JSON.stringify(body) });
    const json: any = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(`1Click quote failed: ${json?.message ?? res.status}`);
    return json as {
      quote: {
        depositAddress?: string; depositMemo?: string; amountIn: string; amountInFormatted: string; amountInUsd: string;
        amountOut: string; amountOutFormatted: string; amountOutUsd: string; timeEstimate: number; deadline?: string;
      };
    };
  }

  async status(depositAddress: string, depositMemo?: string): Promise<{ status: OneClickStatus; swapDetails?: any }> {
    const qs = new URLSearchParams({ depositAddress });
    if (depositMemo) qs.set('depositMemo', depositMemo);
    const res = await this.fetchImpl(`${BASE}/v0/status?${qs}`, { headers: this.headers(true) });
    const json: any = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(`1Click status failed: ${json?.message ?? res.status}`);
    return json;
  }
}

/** Convert a USD amount into the origin token's base units, as an integer string. */
export function usdToBaseUnits(usd: number, priceUsd: number, decimals: number): string {
  if (!(priceUsd > 0)) throw new Error('Token has no USD price');
  const tokens = usd / priceUsd;
  const fixed = tokens.toFixed(Math.min(decimals, 12));
  const [w, f = ''] = fixed.split('.');
  const units = BigInt(w) * 10n ** BigInt(decimals) + BigInt((f + '0'.repeat(decimals)).slice(0, decimals) || '0');
  if (units <= 0n) throw new Error('Amount too small');
  return units.toString();
}

/** A short list of popular origin assets, so the app shows a clean picker. */
export function pickFundingTokens(all: OneClickToken[]): OneClickToken[] {
  const wanted: Array<[string, string]> = [
    ['USDC', 'base'], ['USDC', 'eth'], ['USDC', 'arb'], ['USDC', 'sol'], ['USDT', 'eth'], ['USDT', 'tron'],
    ['ETH', 'eth'], ['ETH', 'base'], ['ETH', 'arb'], ['SOL', 'sol'], ['BTC', 'btc'], ['USDC', 'near'],
  ];
  const out: OneClickToken[] = [];
  for (const [sym, chain] of wanted) {
    const t = all.find(x => x.symbol.toUpperCase() === sym && x.blockchain === chain);
    if (t) out.push(t);
  }
  return out;
}
