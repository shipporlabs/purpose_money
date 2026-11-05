// Purpose Money API — Cloudflare Worker entry point.
import { App, Env, HttpError, required } from './app';
import { verifyIdToken } from './auth';
import * as h from './handlers';
import { verifyPaystackSignature, parseReference } from './paystack';

const routes: Record<string, h.Handler> = {
  'GET /api/banks': h.listBanks,
  'GET /api/fund/tokens': h.fundingTokens,
  'POST /api/families': h.createFamily,
  'POST /api/families/join': h.joinFamily,
  'POST /api/families/leave': h.leaveFamily,
  'POST /api/families/retry-dao': h.retryDao,
  'POST /api/families/chain': h.chainInfo,
  'POST /api/merchants/resolve': h.resolveAccount,
  'POST /api/merchants': h.addMerchant,
  'POST /api/merchants/vote': h.voteMerchant,
  'POST /api/payments': h.requestPayment,
  'POST /api/payments/vote': h.votePayment,
  'POST /api/payments/retry-payout': h.retryPayout,
  'POST /api/changes': h.proposeChange,
  'POST /api/changes/vote': h.voteChange,
  'POST /api/fund/quote': h.fundQuote,
  'POST /api/fund/status': h.fundStatus,
  'POST /api/fund/testnet': h.fundTestnet,
  'POST /api/proposals/get': h.proposalInfo,
};

function cors(env: Env, req: Request): Record<string, string> {
  const allowed = (env.ALLOWED_ORIGIN || '*').split(',').map(s => s.trim());
  const origin = req.headers.get('origin') ?? '';
  const allow = allowed.includes('*') ? '*' : allowed.includes(origin) ? origin : allowed[0];
  return {
    'access-control-allow-origin': allow,
    'access-control-allow-methods': 'GET,POST,OPTIONS',
    'access-control-allow-headers': 'authorization,content-type',
    'access-control-max-age': '86400',
    vary: 'origin',
  };
}

function json(data: unknown, status: number, headers: Record<string, string>) {
  return new Response(JSON.stringify(data), { status, headers: { 'content-type': 'application/json', ...headers } });
}

async function handlePaystackWebhook(app: App, req: Request): Promise<Response> {
  const raw = await req.text();
  const ok = await verifyPaystackSignature(required(app.env, 'PAYSTACK_SECRET_KEY'), raw, req.headers.get('x-paystack-signature'));
  if (!ok) return new Response('bad signature', { status: 401 });
  const event = JSON.parse(raw);
  const ref = parseReference(event?.data?.reference ?? '');
  if (ref && typeof event.event === 'string' && event.event.startsWith('transfer.')) {
    const path = `families/${ref.familyId}/payments/${ref.paymentId}`;
    const paid = event.event === 'transfer.success';
    await app.fs.update(path, {
      status: paid ? 'paid' : 'payout_failed', 'paystack.status': event.data.status ?? event.event, updatedAt: new Date(),
      ...(paid ? { paidAt: new Date(), error: null } : { error: `Paystack reported ${event.event}` }),
    });
  }
  return new Response('ok');
}

export default {
  async fetch(req: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const headers = cors(env, req);
    if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers });
    const url = new URL(req.url);
    try {
      if (url.pathname === '/' || url.pathname === '/api/health') {
        return json({
          ok: true, service: 'purpose-money', network: env.NEAR_NETWORK || 'testnet',
          operator: env.OPERATOR_ACCOUNT_ID ?? null, guardian: env.GUARDIAN_ACCOUNT_ID ?? null,
          paystackMode: env.PAYSTACK_SECRET_KEY?.startsWith('sk_live_') ? 'live' : env.PAYSTACK_SECRET_KEY ? 'test' : 'missing',
          intents: !!(env.ONECLICK_API_KEY && env.INTENTS_RECIPIENT), ai: !!(env.AI_API_KEY && env.AI_BASE_URL),
        }, 200, headers);
      }
      const app = new App(env);
      if (req.method === 'POST' && url.pathname === '/webhooks/paystack') return await handlePaystackWebhook(app, req);

      const handler = routes[`${req.method} ${url.pathname}`];
      if (!handler) throw new HttpError(404, 'Not found');
      const auth = req.headers.get('authorization') ?? '';
      if (!auth.startsWith('Bearer ')) throw new HttpError(401, 'Sign in first');
      let user;
      try { user = await verifyIdToken(auth.slice(7), app.projectId); }
      catch { throw new HttpError(401, 'Your session expired. Sign in again.'); }
      const body = req.method === 'POST' ? await req.json().catch(() => ({})) : Object.fromEntries(url.searchParams);
      const result = await handler(app, user, body, ctx);
      return json(result ?? { ok: true }, 200, headers);
    } catch (e) {
      if (e instanceof HttpError) return json({ error: e.message }, e.status, headers);
      console.error(e);
      return json({ error: e instanceof Error ? e.message : 'Unexpected error' }, 500, headers);
    }
  },
} satisfies ExportedHandler<Env>;
