// Optional: a one-line plain-English explanation of the guardian's decision from any
// OpenAI-compatible endpoint (for example NEAR AI Cloud). It never changes the outcome.
import type { Decision } from './guardian';

export async function explainDecision(
  cfg: { baseUrl?: string; apiKey?: string; model?: string },
  ctx: { amountNgn: number; merchant: string; purpose: string; decision: Decision },
  fetchImpl: typeof fetch = fetch,
): Promise<string | null> {
  if (!cfg.baseUrl || !cfg.apiKey || !cfg.model) return null;
  const failed = ctx.decision.checks.filter(c => !c.passed).map(c => c.detail);
  const prompt = `You are the guardian of a family's shared remittance pot in Nigeria. A parent asked to pay ₦${ctx.amountNgn.toLocaleString('en-NG')} to "${ctx.merchant}" from the ${ctx.purpose} budget. The rule engine decided: ${ctx.decision.outcome}. Failed checks: ${failed.length ? failed.join('; ') : 'none'}. In one friendly sentence (max 30 words) for the siblings abroad, explain the decision. No markdown.`;
  try {
    const res = await fetchImpl(`${cfg.baseUrl.replace(/\/$/, '')}/chat/completions`, {
      method: 'POST',
      headers: { authorization: `Bearer ${cfg.apiKey}`, 'content-type': 'application/json' },
      body: JSON.stringify({ model: cfg.model, messages: [{ role: 'user', content: prompt }], max_tokens: 80, temperature: 0.2 }),
    });
    if (!res.ok) return null;
    const json: any = await res.json();
    const text: string | undefined = json?.choices?.[0]?.message?.content;
    return text ? text.trim().slice(0, 240) : null;
  } catch {
    return null;
  }
}
