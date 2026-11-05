// Request handlers. Every handler receives a verified Firebase user.
import { App, Family, HttpError, loadFamily } from './app';
import { AuthUser } from './auth';
import { newId, inviteCode, Doc } from './firestore';
import { DEFAULT_PURPOSES, DEFAULT_RULES, evaluate, nameMatch, requiredApprovals, lagosDayStart, Rules, Decision } from './guardian';
import { buildPolicy, daoName, createDao, addGuardianKey, proposeTransfer, vote, fundDao, spendableYocto, getProposal } from './dao';
import { Signer, generateKeyPair, explorerAccountUrl, explorerTxUrl, yoctoToNear } from './near';
import { paymentReference, PaystackError } from './paystack';
import { usdToBaseUnits, pickFundingTokens } from './oneclick';
import { explainDecision } from './ai';

type Ctx = { waitUntil(p: Promise<unknown>): void };
export type Handler = (app: App, user: AuthUser, body: any, ctx: Ctx) => Promise<unknown>;

const COUNTED = ['approved', 'paying', 'paid', 'payout_failed'];

function str(v: unknown, name: string, min = 1, max = 80): string {
  if (typeof v !== 'string') throw new HttpError(400, `${name} is required`);
  const s = v.trim();
  if (s.length < min || s.length > max) throw new HttpError(400, `${name} must be ${min}–${max} characters`);
  return s;
}
function int(v: unknown, name: string, min: number, max: number): number {
  const n = typeof v === 'string' ? Number(v) : v;
  if (typeof n !== 'number' || !Number.isFinite(n) || Math.round(n) !== n || n < min || n > max) {
    throw new HttpError(400, `${name} must be a whole number between ${min} and ${max}`);
  }
  return n;
}
function displayName(user: AuthUser, profile?: Record<string, any> | null) {
  return (profile?.displayName as string) || user.name || user.email?.split('@')[0] || 'Family member';
}
function errMessage(e: unknown) { return e instanceof Error ? e.message.slice(0, 500) : String(e); }

// ---------------- families ----------------

export const createFamily: Handler = async (app, user, body, ctx) => {
  const name = str(body.name, 'Family name', 2, 40);
  const profile = await app.fs.get(`users/${user.uid}`);
  if (profile?.data.familyId) throw new HttpError(409, 'You are already in a family');
  const familyId = newId();
  const dao = daoName(name, newId(4));
  const daoId = `${dao}.${app.factory}`;
  const me = displayName(user, profile?.data);
  const family: Family = {
    name, createdBy: user.uid, siblingUids: [user.uid], parentUids: [], memberUids: [user.uid],
    memberNames: { [user.uid]: me }, inviteCode: inviteCode(),
    purposes: structuredClone(DEFAULT_PURPOSES), rules: { ...DEFAULT_RULES }, balanceNgn: 0, contributedNgn: { [user.uid]: 0 },
    network: app.network, dao: { id: daoId, status: 'creating' },
  };
  await app.fs.create(`families/${familyId}`, { ...family, createdAt: new Date() });
  await app.fs.update(`users/${user.uid}`, { familyId, role: 'sibling', displayName: me });
  ctx.waitUntil(setupDao(app, familyId, dao, name));
  return { familyId, inviteCode: family.inviteCode, daoId };
};

async function setupDao(app: App, familyId: string, name: string, familyName: string) {
  const path = `families/${familyId}`;
  try {
    const operator = app.operator();
    const guardian = app.guardianFullAccess();
    const daoId = `${name}.${app.factory}`;
    let createTx: string | undefined;
    if (!(await app.near.viewAccount(daoId))) {
      const policy = buildPolicy({ councilAccount: operator.accountId, guardianAccount: guardian.accountId, proposalBondYocto: app.bondYocto });
      const r = await createDao(app.near, operator, app.factory, name, `Purpose Money family pot: ${familyName}`, policy, app.env.DAO_CREATE_DEPOSIT_NEAR || '6');
      createTx = r.tx.hash;
    }
    let secret = await app.fs.get(`_secrets/${familyId}`);
    if (!secret) {
      const keys = generateKeyPair();
      await addGuardianKey(app.near, guardian, daoId, keys.publicKey);
      await app.fs.update(`_secrets/${familyId}`, { guardianKey: keys.secretKey, publicKey: keys.publicKey, daoId });
      secret = await app.fs.get(`_secrets/${familyId}`);
    }
    await app.fs.update(path, {
      'dao.status': 'active', 'dao.error': null, 'dao.guardianKey': secret!.data.publicKey,
      ...(createTx ? { 'dao.createTx': createTx } : {}), 'dao.activatedAt': new Date(),
    });
  } catch (e) {
    await app.fs.update(path, { 'dao.status': 'failed', 'dao.error': errMessage(e) });
  }
}

export const retryDao: Handler = async (app, user, body, ctx) => {
  const fam = await loadFamily(app, body.familyId, user.uid, { sibling: true });
  if (fam.data.dao.status === 'active') return { status: 'active' };
  await app.fs.update(fam.path, { 'dao.status': 'creating', 'dao.error': null });
  ctx.waitUntil(setupDao(app, fam.id, fam.data.dao.id.split('.')[0], fam.data.name));
  return { status: 'creating' };
};

export const joinFamily: Handler = async (app, user, body) => {
  const code = str(body.inviteCode, 'Invite code', 6, 6).toUpperCase();
  const role = body.role === 'parent' ? 'parent' : body.role === 'sibling' ? 'sibling' : null;
  if (!role) throw new HttpError(400, 'role must be "sibling" or "parent"');
  const profile = await app.fs.get(`users/${user.uid}`);
  if (profile?.data.familyId) throw new HttpError(409, 'You are already in a family');
  const [fam] = await app.fs.query('', 'families', [{ field: 'inviteCode', op: 'EQUAL', value: code }], 1);
  if (!fam) throw new HttpError(404, 'No family uses that invite code');
  const me = displayName(user, profile?.data);
  await app.mutate<Family>(fam.path, f => {
    if (f.memberUids.includes(user.uid)) return null;
    const patch: Record<string, unknown> = {
      memberUids: [...f.memberUids, user.uid],
      [`memberNames.${user.uid}`]: me,
    };
    if (role === 'sibling') { patch.siblingUids = [...f.siblingUids, user.uid]; patch[`contributedNgn.${user.uid}`] = 0; }
    else patch.parentUids = [...f.parentUids, user.uid];
    return patch;
  });
  await app.fs.update(`users/${user.uid}`, { familyId: fam.id, role, displayName: me });
  return { familyId: fam.id, role };
};

export const leaveFamily: Handler = async (app, user, body) => {
  const fam = await loadFamily(app, body.familyId, user.uid);
  if (fam.data.siblingUids.length === 1 && fam.data.siblingUids[0] === user.uid) {
    throw new HttpError(400, 'You are the only sibling. Invite another sibling before leaving.');
  }
  await app.mutate<Family>(fam.path, f => ({
    memberUids: f.memberUids.filter(u => u !== user.uid),
    siblingUids: f.siblingUids.filter(u => u !== user.uid),
    parentUids: f.parentUids.filter(u => u !== user.uid),
  }));
  await app.fs.update(`users/${user.uid}`, { familyId: null, role: null });
  return { ok: true };
};

export const chainInfo: Handler = async (app, user, body) => {
  const fam = await loadFamily(app, body.familyId, user.uid);
  const daoId = fam.data.dao.id;
  const acct = await app.near.viewAccount(daoId);
  let lastProposalId: number | null = null;
  let roles: Array<{ name: string; members: string[]; permissions: string[] }> = [];
  if (acct) {
    try { lastProposalId = await app.near.viewFunction<number>(daoId, 'get_last_proposal_id'); } catch { /* older DAO */ }
    try {
      const policy = await app.near.viewFunction<any>(daoId, 'get_policy');
      roles = (policy?.roles ?? []).map((r: any) => ({ name: r.name, members: r.kind?.Group ?? [], permissions: r.permissions ?? [] }));
    } catch { /* ignore */ }
  }
  const spendable = acct ? await spendableYocto(app.near, daoId) : 0n;
  return {
    daoId, network: app.network, exists: !!acct, explorer: explorerAccountUrl(app.network, daoId),
    balanceNear: acct ? yoctoToNear(acct.amount) : 0, spendableNear: yoctoToNear(spendable),
    nearUsd: await app.nearUsd(), ngnPerUsd: app.ngnPerUsd, lastProposalId, roles,
  };
};

// ---------------- merchants ----------------

export const listBanks: Handler = async app => ({ banks: await app.banks(), testMode: app.paystack.isTestMode });

export const resolveAccount: Handler = async (app, _user, body) => {
  const accountNumber = str(body.accountNumber, 'Account number', 10, 10);
  if (!/^\d{10}$/.test(accountNumber)) throw new HttpError(400, 'Account number must be 10 digits');
  const bankCode = str(body.bankCode, 'Bank', 2, 10);
  try {
    const r = await app.paystack.resolveAccount(accountNumber, bankCode);
    return { accountName: r.account_name, accountNumber: r.account_number };
  } catch (e) {
    if (e instanceof PaystackError) throw new HttpError(e.status === 429 ? 429 : 422, `Could not verify this account: ${e.message}`);
    throw e;
  }
};

export const addMerchant: Handler = async (app, user, body) => {
  const fam = await loadFamily(app, body.familyId, user.uid);
  const displayNameIn = str(body.displayName, 'Shop name', 2, 50);
  const category = str(body.category, 'Purpose', 1, 20);
  if (!fam.data.purposes[category]) throw new HttpError(400, 'Choose one of the family purposes');
  const accountNumber = str(body.accountNumber, 'Account number', 10, 10);
  if (!/^\d{10}$/.test(accountNumber)) throw new HttpError(400, 'Account number must be 10 digits');
  const bankCode = str(body.bankCode, 'Bank', 2, 10);
  const bankName = typeof body.bankName === 'string' ? body.bankName.slice(0, 80) : '';

  const existing = await app.fs.query(fam.path, 'merchants', [{ field: 'accountNumber', op: 'EQUAL', value: accountNumber }], 10);
  if (existing.some(m => m.data.bankCode === bankCode && m.data.status !== 'rejected')) throw new HttpError(409, 'This account is already on your list');

  let accountName: string;
  try { accountName = (await app.paystack.resolveAccount(accountNumber, bankCode)).account_name; }
  catch (e) { throw new HttpError(422, `Could not verify this account: ${errMessage(e)}`); }
  const recipient = await app.paystack.createRecipient(accountName, accountNumber, bankCode);

  const isSibling = fam.data.siblingUids.includes(user.uid);
  const need = requiredApprovals(fam.data.rules, fam.data.siblingUids.length);
  const approvals = isSibling ? [user.uid] : [];
  const approved = approvals.length >= need;
  const id = newId();
  const merchant = {
    displayName: displayNameIn, category, bankCode, bankName, accountNumber, accountName,
    nameMatch: nameMatch(displayNameIn, accountName), recipientCode: recipient.recipient_code,
    status: approved ? 'approved' : 'pending', approvals, rejections: [], approvalsNeeded: need,
    addedBy: user.uid, addedByName: fam.data.memberNames[user.uid] ?? 'Family member',
    createdAt: new Date(), approvedAt: approved ? new Date() : null,
  };
  await app.fs.create(`${fam.path}/merchants/${id}`, merchant);
  return { merchantId: id, status: merchant.status, accountName, nameMatch: merchant.nameMatch };
};

export const voteMerchant: Handler = async (app, user, body) => {
  const fam = await loadFamily(app, body.familyId, user.uid, { sibling: true });
  const path = `${fam.path}/merchants/${str(body.merchantId, 'merchantId', 6, 40)}`;
  const approve = body.approve === true;
  const need = requiredApprovals(fam.data.rules, fam.data.siblingUids.length);
  const m = await app.mutate<any>(path, d => {
    if (d.status !== 'pending') throw new HttpError(409, `This shop is already ${d.status}`);
    const approvals: string[] = (d.approvals ?? []).filter((u: string) => u !== user.uid);
    const rejections: string[] = (d.rejections ?? []).filter((u: string) => u !== user.uid);
    (approve ? approvals : rejections).push(user.uid);
    const patch: Record<string, unknown> = { approvals, rejections, approvalsNeeded: need };
    if (approvals.length >= need) { patch.status = 'approved'; patch.approvedAt = new Date(); }
    else if (rejections.length >= need) patch.status = 'rejected';
    return patch;
  });
  return { status: m.status };
};

// ---------------- payments ----------------

export const requestPayment: Handler = async (app, user, body, ctx) => {
  const fam = await loadFamily(app, body.familyId, user.uid);
  const merchantId = str(body.merchantId, 'merchantId', 6, 40);
  const amountNgn = int(body.amountNgn, 'Amount', 100, 5_000_000);
  const note = typeof body.note === 'string' ? body.note.trim().slice(0, 120) : '';
  const merchant = await app.fs.get<any>(`${fam.path}/merchants/${merchantId}`);
  if (!merchant) throw new HttpError(404, 'Shop not found');

  const now = Date.now();
  const today = await app.fs.query(fam.path, 'payments', [{ field: 'createdAt', op: 'GREATER_THAN_OR_EQUAL', value: new Date(lagosDayStart(now)) }], 200);
  const countedToday = today.filter(p => COUNTED.includes(p.data.status));
  const history = await app.fs.query(fam.path, 'payments', [{ field: 'merchantId', op: 'EQUAL', value: merchantId }], 50);

  const decision = evaluate({
    amountNgn, category: merchant.data.category, potReady: fam.data.dao.status === 'active',
    merchant: {
      status: merchant.data.status, category: merchant.data.category, nameMatch: merchant.data.nameMatch ?? 0,
      approvedAtMs: merchant.data.approvedAt instanceof Date ? merchant.data.approvedAt.getTime() : null,
    },
    family: { balanceNgn: fam.data.balanceNgn ?? 0, purposes: fam.data.purposes, rules: fam.data.rules },
    merchantPaidTodayNgn: countedToday.filter(p => p.data.merchantId === merchantId).reduce((s, p) => s + p.data.amountNgn, 0),
    familyPaymentsToday: countedToday.length,
    recentAmountsAtMerchant: history.filter(p => p.data.status === 'paid').map(p => p.data.amountNgn),
    nowMs: now,
  });

  const id = newId();
  const purpose = fam.data.purposes[merchant.data.category];
  const payment = {
    merchantId, merchantName: merchant.data.displayName, accountName: merchant.data.accountName,
    category: merchant.data.category, purposeLabel: purpose?.label ?? merchant.data.category,
    amountNgn, note, requestedBy: user.uid, requestedByName: fam.data.memberNames[user.uid] ?? 'Family member',
    status: decision.outcome, decision: { ...decision, aiNote: null, decidedAt: new Date() },
    approvals: [], rejections: [], approvalsNeeded: requiredApprovals(fam.data.rules, fam.data.siblingUids.length),
    onchain: {}, paystack: {}, createdAt: new Date(), updatedAt: new Date(),
  };
  await app.fs.create(`${fam.path}/payments/${id}`, payment);

  ctx.waitUntil((async () => {
    const note = await explainDecision(
      { baseUrl: app.env.AI_BASE_URL, apiKey: app.env.AI_API_KEY, model: app.env.AI_MODEL },
      { amountNgn, merchant: merchant.data.displayName, purpose: payment.purposeLabel, decision },
    );
    if (note) await app.fs.update(`${fam.path}/payments/${id}`, { 'decision.aiNote': note });
  })().catch(() => undefined));
  if (decision.outcome === 'approved') ctx.waitUntil(executePayment(app, fam.id, id, 'guardian'));
  return { paymentId: id, outcome: decision.outcome, reason: decision.reason };
};

export const votePayment: Handler = async (app, user, body, ctx) => {
  const fam = await loadFamily(app, body.familyId, user.uid, { sibling: true });
  const paymentId = str(body.paymentId, 'paymentId', 6, 40);
  const path = `${fam.path}/payments/${paymentId}`;
  const approve = body.approve === true;
  const need = requiredApprovals(fam.data.rules, fam.data.siblingUids.length);
  const p = await app.mutate<any>(path, d => {
    if (d.status !== 'escalated') throw new HttpError(409, `This payment is already ${d.status}`);
    const approvals: string[] = (d.approvals ?? []).filter((u: string) => u !== user.uid);
    const rejections: string[] = (d.rejections ?? []).filter((u: string) => u !== user.uid);
    (approve ? approvals : rejections).push(user.uid);
    const patch: Record<string, unknown> = { approvals, rejections, approvalsNeeded: need, updatedAt: new Date() };
    if (approvals.length >= need) { patch.status = 'approved'; patch['decision.overriddenBy'] = approvals; }
    else if (rejections.length >= need) patch.status = 'rejected';
    return patch;
  });
  if (p.status === 'approved') ctx.waitUntil(executePayment(app, fam.id, paymentId, 'council'));
  return { status: p.status };
};

export async function executePayment(app: App, familyId: string, paymentId: string, via: 'guardian' | 'council') {
  const famPath = `families/${familyId}`;
  const path = `${famPath}/payments/${paymentId}`;
  const doc = await app.fs.get<any>(path);
  if (!doc || doc.data.status !== 'approved') return;
  try { await app.fs.update(path, { status: 'paying', updatedAt: new Date() }, { updateTime: doc.updateTime }); }
  catch { return; } // someone else claimed it

  const p = doc.data;
  let chainApproved = false;
  try {
    const fam = await app.fs.get<Family>(famPath);
    const merchant = await app.fs.get<any>(`${famPath}/merchants/${p.merchantId}`);
    if (!fam || !merchant) throw new Error('Family or shop no longer exists');
    const purpose = fam.data.purposes[p.category];
    if (!purpose || purpose.budgetNgn - purpose.spentNgn < p.amountNgn) throw new Error('The purpose budget no longer covers this payment');
    if ((fam.data.balanceNgn ?? 0) < p.amountNgn) throw new Error('The pot balance no longer covers this payment');
    if (merchant.data.status !== 'approved') throw new Error('The shop is no longer approved');

    const daoId = fam.data.dao.id;
    const yocto = await app.ngnToYocto(p.amountNgn);
    const spendable = await spendableYocto(app.near, daoId);
    if (spendable < yocto) throw new Error(`The family DAO holds ${yoctoToNear(spendable)} NEAR but this payment needs ${yoctoToNear(yocto)} NEAR`);

    const operator = app.operator();
    const { id: proposalId, tx: ptx } = await proposeTransfer(app.near, operator, daoId, app.treasury, yocto,
      `Purpose Money: ₦${p.amountNgn.toLocaleString('en-NG')} to ${p.merchantName} (${p.purposeLabel}) [${paymentId}]`, app.bondYocto);
    await app.fs.update(path, {
      'onchain.proposalId': proposalId, 'onchain.proposeTx': ptx.hash, 'onchain.proposeUrl': explorerTxUrl(app.network, ptx.hash),
      'onchain.amountNear': yoctoToNear(yocto, 6), 'onchain.daoId': daoId,
    });

    let voter: Signer;
    if (via === 'guardian') {
      const secret = await app.fs.get<any>(`_secrets/${familyId}`);
      if (!secret) throw new Error('Guardian key for this family is missing');
      voter = new Signer(app.guardianFullAccess().accountId, secret.data.guardianKey);
    } else voter = operator;
    const { tx: vtx, status } = await vote(app.near, voter, daoId, proposalId, 'VoteApprove');
    if (status !== 'Approved') throw new Error(`DAO proposal ${proposalId} is ${status}, not Approved`);
    chainApproved = true;
    await app.fs.update(path, {
      'onchain.approveTx': vtx.hash, 'onchain.approveUrl': explorerTxUrl(app.network, vtx.hash),
      'onchain.status': 'Approved', 'onchain.approvedBy': via === 'guardian' ? 'guardian' : 'family council',
    });
    await app.fs.increment(famPath, { balanceNgn: -p.amountNgn, [`purposes.${p.category}.spentNgn`]: p.amountNgn });

    await payout(app, familyId, paymentId, merchant.data.recipientCode, p.amountNgn, `${p.purposeLabel} for family - ${p.merchantName}`);
  } catch (e) {
    await app.fs.update(path, {
      status: chainApproved ? 'payout_failed' : 'failed', error: errMessage(e), updatedAt: new Date(),
    });
  }
}

async function payout(app: App, familyId: string, paymentId: string, recipientCode: string, amountNgn: number, reason: string) {
  const path = `families/${familyId}/payments/${paymentId}`;
  const reference = paymentReference(familyId, paymentId);
  try {
    const t = await app.paystack.initiateTransfer(amountNgn * 100, recipientCode, reference, reason);
    const status = t.status === 'success' ? 'paid' : t.status === 'otp' ? 'payout_failed' : 'paying';
    await app.fs.update(path, {
      status, 'paystack.reference': reference, 'paystack.transferCode': t.transfer_code ?? null, 'paystack.status': t.status,
      'paystack.testMode': app.paystack.isTestMode, updatedAt: new Date(), ...(status === 'paid' ? { paidAt: new Date(), error: null } : {}),
      ...(t.status === 'otp' ? { error: 'Paystack wants an OTP. Turn off "Confirm transfers before sending" in the Paystack dashboard.' } : {}),
    });
  } catch (e) {
    await app.fs.update(path, { status: 'payout_failed', 'paystack.reference': reference, error: errMessage(e), updatedAt: new Date() });
  }
}

export const retryPayout: Handler = async (app, user, body) => {
  const fam = await loadFamily(app, body.familyId, user.uid, { sibling: true });
  const paymentId = str(body.paymentId, 'paymentId', 6, 40);
  const p = await app.fs.get<any>(`${fam.path}/payments/${paymentId}`);
  if (!p) throw new HttpError(404, 'Payment not found');
  if (p.data.status !== 'payout_failed' || p.data.onchain?.status !== 'Approved') throw new HttpError(409, 'Only approved payments with a failed payout can be retried');
  const merchant = await app.fs.get<any>(`${fam.path}/merchants/${p.data.merchantId}`);
  await payout(app, fam.id, paymentId, merchant!.data.recipientCode, p.data.amountNgn, `${p.data.purposeLabel} for family - ${p.data.merchantName}`);
  return { ok: true };
};

// ---------------- family changes (budgets, rules, new month) ----------------

function validateChange(type: string, payload: any, fam: Family) {
  if (type === 'budgets') {
    const input = payload?.purposes;
    if (!input || typeof input !== 'object') throw new HttpError(400, 'purposes are required');
    const keys = Object.keys(input);
    if (keys.length < 1 || keys.length > 8) throw new HttpError(400, 'Use between 1 and 8 purposes');
    const purposes: Record<string, { label: string; budgetNgn: number }> = {};
    for (const k of keys) {
      if (!/^[a-z][a-z0-9_]{1,19}$/.test(k)) throw new HttpError(400, `Invalid purpose key ${k}`);
      purposes[k] = { label: str(input[k]?.label, 'Purpose name', 1, 24), budgetNgn: int(input[k]?.budgetNgn, 'Budget', 0, 50_000_000) };
    }
    return { purposes };
  }
  if (type === 'rules') {
    const r = payload?.rules ?? {};
    const out: Partial<Rules> = {};
    if (r.autoApproveLimitNgn !== undefined) out.autoApproveLimitNgn = int(r.autoApproveLimitNgn, 'Auto-approve limit', 0, 10_000_000);
    if (r.dailyCapPerMerchantNgn !== undefined) out.dailyCapPerMerchantNgn = int(r.dailyCapPerMerchantNgn, 'Daily cap', 0, 20_000_000);
    if (r.newMerchantCooldownHours !== undefined) out.newMerchantCooldownHours = int(r.newMerchantCooldownHours, 'Cooling-off hours', 0, 720);
    if (r.maxPaymentsPerDay !== undefined) out.maxPaymentsPerDay = int(r.maxPaymentsPerDay, 'Payments per day', 1, 100);
    if (r.siblingApprovalsRequired !== undefined) out.siblingApprovalsRequired = int(r.siblingApprovalsRequired, 'Approvals needed', 1, 10);
    if (!Object.keys(out).length) throw new HttpError(400, 'No rule changes given');
    return { rules: out };
  }
  if (type === 'new_month') return {};
  throw new HttpError(400, 'type must be budgets, rules or new_month');
  void fam;
}

function changePatch(type: string, payload: any, fam: Family): Record<string, unknown> {
  if (type === 'budgets') {
    const purposes: Record<string, unknown> = {};
    for (const [k, v] of Object.entries<any>(payload.purposes)) {
      purposes[k] = { label: v.label, budgetNgn: v.budgetNgn, spentNgn: fam.purposes[k]?.spentNgn ?? 0 };
    }
    return { purposes };
  }
  if (type === 'rules') return { rules: { ...fam.rules, ...payload.rules } };
  const purposes: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(fam.purposes)) purposes[k] = { ...v, spentNgn: 0 };
  return { purposes, lastMonthResetAt: new Date() };
}

export const proposeChange: Handler = async (app, user, body) => {
  const fam = await loadFamily(app, body.familyId, user.uid, { sibling: true });
  const type = str(body.type, 'type', 3, 20);
  const payload = validateChange(type, body.payload, fam.data);
  const need = requiredApprovals(fam.data.rules, fam.data.siblingUids.length);
  const id = newId();
  const applied = need <= 1;
  await app.fs.create(`${fam.path}/changes/${id}`, {
    type, payload, proposedBy: user.uid, proposedByName: fam.data.memberNames[user.uid] ?? 'Sibling',
    approvals: [user.uid], rejections: [], approvalsNeeded: need, status: applied ? 'applied' : 'pending', createdAt: new Date(),
  });
  if (applied) await app.mutate<Family>(fam.path, f => changePatch(type, payload, f));
  return { changeId: id, status: applied ? 'applied' : 'pending' };
};

export const voteChange: Handler = async (app, user, body) => {
  const fam = await loadFamily(app, body.familyId, user.uid, { sibling: true });
  const path = `${fam.path}/changes/${str(body.changeId, 'changeId', 6, 40)}`;
  const approve = body.approve === true;
  const need = requiredApprovals(fam.data.rules, fam.data.siblingUids.length);
  const c = await app.mutate<any>(path, d => {
    if (d.status !== 'pending') throw new HttpError(409, `This change is already ${d.status}`);
    const approvals: string[] = (d.approvals ?? []).filter((u: string) => u !== user.uid);
    const rejections: string[] = (d.rejections ?? []).filter((u: string) => u !== user.uid);
    (approve ? approvals : rejections).push(user.uid);
    const patch: Record<string, unknown> = { approvals, rejections, approvalsNeeded: need };
    if (approvals.length >= need) patch.status = 'applied';
    else if (rejections.length >= need) patch.status = 'rejected';
    return patch;
  });
  if (c.status === 'applied') await app.mutate<Family>(fam.path, f => changePatch(c.type, c.payload, f));
  return { status: c.status };
};

// ---------------- funding ----------------

export const fundingTokens: Handler = async app => ({
  tokens: pickFundingTokens(await app.tokens()).map(t => ({ assetId: t.assetId, symbol: t.symbol, blockchain: t.blockchain, decimals: t.decimals, price: t.price })),
  intentsEnabled: !!(app.env.ONECLICK_API_KEY && app.env.INTENTS_RECIPIENT),
  testnetTopupMaxUsd: Number(app.env.TESTNET_TOPUP_MAX_USD || '50'),
  ngnPerUsd: app.ngnPerUsd,
});

export const fundQuote: Handler = async (app, user, body) => {
  const fam = await loadFamily(app, body.familyId, user.uid, { sibling: true });
  if (!app.env.ONECLICK_API_KEY || !app.env.INTENTS_RECIPIENT) throw new HttpError(501, 'Cross-chain funding is not configured yet (ONECLICK_API_KEY / INTENTS_RECIPIENT).');
  const amountUsd = int(body.amountUsd, 'Amount (USD)', 1, 5000);
  const refundTo = str(body.refundTo, 'Refund address', 8, 120);
  const tokens = await app.tokens();
  const origin = tokens.find(t => t.assetId === body.assetId);
  if (!origin) throw new HttpError(400, 'Unsupported token');
  const dest = tokens.find(t => t.blockchain === 'near' && t.symbol.toUpperCase() === 'USDC');
  if (!dest) throw new HttpError(503, 'USDC on NEAR is not available on 1Click right now');
  const q = await app.oneclick.quote({
    originAsset: origin.assetId, destinationAsset: dest.assetId, amount: usdToBaseUnits(amountUsd, origin.price, origin.decimals),
    refundTo, recipient: app.env.INTENTS_RECIPIENT, dry: false,
  });
  if (!q.quote.depositAddress) throw new HttpError(502, '1Click did not return a deposit address');
  const id = newId();
  const contribution = {
    uid: user.uid, name: fam.data.memberNames[user.uid] ?? 'Sibling', method: 'intents', status: 'awaiting_deposit',
    amountUsd, originAsset: origin.assetId, originSymbol: origin.symbol, originChain: origin.blockchain,
    amountIn: q.quote.amountInFormatted, depositAddress: q.quote.depositAddress, depositMemo: q.quote.depositMemo ?? null,
    expectedOutUsd: Number(q.quote.amountOutUsd), timeEstimate: q.quote.timeEstimate, deadline: q.quote.deadline ?? null,
    refundTo, credited: false, createdAt: new Date(),
  };
  await app.fs.create(`${fam.path}/contributions/${id}`, contribution);
  return { contributionId: id, ...contribution };
};

export const fundStatus: Handler = async (app, user, body) => {
  const fam = await loadFamily(app, body.familyId, user.uid);
  const path = `${fam.path}/contributions/${str(body.contributionId, 'contributionId', 6, 40)}`;
  const c = await app.fs.get<any>(path);
  if (!c) throw new HttpError(404, 'Contribution not found');
  if (c.data.method !== 'intents' || c.data.credited) return { status: c.data.status };
  const s = await app.oneclick.status(c.data.depositAddress, c.data.depositMemo ?? undefined);
  const status = s.status.toLowerCase();
  if (s.status === 'SUCCESS') {
    const usd = Number(s.swapDetails?.amountOutUsd ?? c.data.expectedOutUsd);
    await credit(app, fam, c, usd);
    return { status: 'credited' };
  }
  if (status !== c.data.status) await app.fs.update(path, { status, oneclickStatus: s.status });
  return { status };
};

export const fundTestnet: Handler = async (app, user, body) => {
  const fam = await loadFamily(app, body.familyId, user.uid, { sibling: true });
  if (app.network !== 'testnet') throw new HttpError(400, 'Test top-ups only work on testnet');
  const max = Number(app.env.TESTNET_TOPUP_MAX_USD || '50');
  const amountUsd = int(body.amountUsd, 'Amount (USD)', 1, max);
  if (fam.data.dao.status !== 'active') throw new HttpError(409, 'The family pot is still being set up on NEAR');
  const id = newId();
  await app.fs.create(`${fam.path}/contributions/${id}`, {
    uid: user.uid, name: fam.data.memberNames[user.uid] ?? 'Sibling', method: 'testnet', status: 'crediting',
    amountUsd, credited: false, createdAt: new Date(),
  });
  const c = await app.fs.get<any>(`${fam.path}/contributions/${id}`);
  await credit(app, fam, c!, amountUsd);
  const after = await app.fs.get<any>(`${fam.path}/contributions/${id}`);
  if (after?.data.status !== 'credited') throw new HttpError(502, after?.data.error ?? 'Top-up failed');
  return { contributionId: id, status: 'credited', amountNgn: after.data.amountNgn };
};

async function credit(app: App, fam: Doc<Family>, c: Doc<any>, usd: number) {
  try { await app.fs.update(c.path, { credited: true, status: 'crediting' }, { updateTime: c.updateTime }); }
  catch { return; } // already being credited
  try {
    const yocto = await app.usdToYocto(usd);
    const tx = await fundDao(app.near, app.operator(), fam.data.dao.id, yocto);
    const amountNgn = Math.floor(usd * app.ngnPerUsd);
    await app.fs.update(c.path, {
      status: 'credited', amountNgn, creditedUsd: usd, mirrorTx: tx.hash, mirrorUrl: explorerTxUrl(app.network, tx.hash),
      amountNear: yoctoToNear(yocto, 6), creditedAt: new Date(),
    });
    await app.fs.increment(fam.path, { balanceNgn: amountNgn, [`contributedNgn.${c.data.uid}`]: amountNgn });
  } catch (e) {
    await app.fs.update(c.path, { status: 'credit_failed', credited: false, error: errMessage(e) });
  }
}

export const proposalInfo: Handler = async (app, user, body) => {
  const fam = await loadFamily(app, body.familyId, user.uid);
  return getProposal(app.near, fam.data.dao.id, int(body.proposalId, 'proposalId', 0, 1_000_000));
};

export type { Decision };
