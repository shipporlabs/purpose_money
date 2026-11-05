// Sputnik DAO helpers: each family pot is a DAO on NEAR.
import { NearClient, Signer, functionCall, addFunctionCallKey, transfer, nearToYocto, publicKeyFromString, TGAS, TxResult } from './near';

export function buildPolicy(opts: { councilAccount: string; guardianAccount: string; proposalBondYocto: bigint }) {
  if (opts.councilAccount === opts.guardianAccount) throw new Error('Guardian and operator must be different NEAR accounts');
  return {
    roles: [
      // Guardian first: it may only vote on transfer proposals (approve or reject). Nothing else.
      { name: 'guardian', kind: { Group: [opts.guardianAccount] }, permissions: ['transfer:VoteApprove', 'transfer:VoteReject'], vote_policy: {} },
      // Council relays family decisions (sibling votes collected in the app) and creates proposals.
      {
        name: 'council', kind: { Group: [opts.councilAccount] },
        permissions: ['*:AddProposal', '*:VoteApprove', '*:VoteReject', '*:VoteRemove', '*:Finalize'], vote_policy: {},
      },
    ],
    default_vote_policy: { weight_kind: 'RoleWeight', quorum: '0', threshold: [1, 2] },
    proposal_bond: opts.proposalBondYocto.toString(),
    proposal_period: '604800000000000',
    bounty_bond: '1000000000000000000000000',
    bounty_forgiveness_period: '86400000000000',
  };
}

export function daoName(familyName: string, suffix: string): string {
  const slug = familyName.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 24) || 'family';
  return `pm-${slug}-${suffix}`.replace(/-+/g, '-');
}

export async function createDao(near: NearClient, operator: Signer, factory: string, name: string, purpose: string, policy: unknown, depositNear: string): Promise<{ daoId: string; tx: TxResult }> {
  const args = btoa(JSON.stringify({ config: { name, purpose, metadata: '' }, policy }));
  const tx = await near.sendTransaction(operator, factory, [functionCall('create', { name, args }, 300n * TGAS, nearToYocto(depositNear))]);
  const daoId = `${name}.${factory}`;
  const acct = await near.viewAccount(daoId);
  if (!acct) throw new Error(`DAO ${daoId} was not created (factory call ${tx.hash})`);
  return { daoId, tx };
}

/** Give the guardian a key that can only call act_proposal on this one DAO. */
export async function addGuardianKey(near: NearClient, guardian: Signer, daoId: string, publicKey: string, allowanceNear = '0.5') {
  return near.sendTransaction(guardian, guardian.accountId, [
    addFunctionCallKey(publicKeyFromString(publicKey), daoId, ['act_proposal'], nearToYocto(allowanceNear)),
  ]);
}

export async function proposeTransfer(near: NearClient, proposer: Signer, daoId: string, receiverId: string, amountYocto: bigint, description: string, bondYocto: bigint) {
  const tx = await near.sendTransaction(proposer, daoId, [functionCall('add_proposal', {
    proposal: { description, kind: { Transfer: { token_id: '', receiver_id: receiverId, amount: amountYocto.toString() } } },
  }, 100n * TGAS, bondYocto)]);
  const id = typeof tx.value === 'number' ? tx.value : Number(tx.value);
  if (!Number.isFinite(id)) throw new Error(`add_proposal returned no id (tx ${tx.hash})`);
  return { id, tx };
}

export async function getProposal(near: NearClient, daoId: string, id: number) {
  return near.viewFunction<{ id: number; status: string; kind: unknown; proposer: string }>(daoId, 'get_proposal', { id });
}

export async function vote(near: NearClient, voter: Signer, daoId: string, id: number, action: 'VoteApprove' | 'VoteReject') {
  const proposal = await getProposal(near, daoId, id);
  // act_proposal requires the proposal kind to guard against races; pass it through unchanged.
  const tx = await near.sendTransaction(voter, daoId, [functionCall('act_proposal', { id, action, proposal: proposal.kind }, 200n * TGAS)]);
  const after = await getProposal(near, daoId, id);
  return { tx, status: after.status };
}

export async function fundDao(near: NearClient, funder: Signer, daoId: string, amountYocto: bigint) {
  return near.sendTransaction(funder, daoId, [transfer(amountYocto)]);
}

/** Spendable NEAR on an account (balance minus storage staking, minus a small safety reserve). */
export async function spendableYocto(near: NearClient, accountId: string): Promise<bigint> {
  const acct = await near.viewAccount(accountId);
  if (!acct) return 0n;
  const storage = BigInt(acct.storage_usage) * 10n ** 19n;
  const reserve = nearToYocto('0.05');
  const free = BigInt(acct.amount) - storage - reserve;
  return free > 0n ? free : 0n;
}
