import { describe, it, expect } from 'vitest';
import { transactions, utils } from 'near-api-js';
import { sha256 } from '@noble/hashes/sha2.js';
import bs58 from 'bs58';
import {
  serializeTransaction, signTransaction, Signer, functionCall, transfer, addFunctionCallKey,
  nearToYocto, yoctoToNear, generateKeyPair, parseOutcome, toBase64, fromBase64, TGAS,
} from '../src/near';

const kp = utils.KeyPair.fromRandom('ed25519');
const secret = kp.toString();
const blockHash = sha256(new TextEncoder().encode('block'));

describe('borsh serialization matches near-api-js', () => {
  it('function call + transfer', () => {
    const signer = new Signer('operator.testnet', secret);
    expect(signer.publicKeyString).toBe(kp.getPublicKey().toString());
    const args = { proposal: { description: 'pay', kind: { Transfer: { token_id: '', receiver_id: 'treasury.testnet', amount: '1000' } } } };
    const ours = serializeTransaction({
      signerId: 'operator.testnet', publicKey: signer.publicKey, nonce: 42n, receiverId: 'dao.sputnikv2.testnet',
      blockHash, actions: [functionCall('add_proposal', args, 100n * TGAS, nearToYocto('0.1')), transfer(nearToYocto('1.5'))],
    });
    const tx = transactions.createTransaction(
      'operator.testnet', kp.getPublicKey(), 'dao.sputnikv2.testnet', 42n,
      [transactions.functionCall('add_proposal', args, 100n * TGAS, nearToYocto('0.1')), transactions.transfer(nearToYocto('1.5'))],
      blockHash,
    );
    expect(Buffer.from(ours).toString('hex')).toBe(Buffer.from(transactions.encodeTransaction(tx)).toString('hex'));
  });

  it('add function-call access key', () => {
    const signer = new Signer('guardian.testnet', secret);
    const newKey = utils.KeyPair.fromRandom('ed25519').getPublicKey();
    const ours = serializeTransaction({
      signerId: 'guardian.testnet', publicKey: signer.publicKey, nonce: 7n, receiverId: 'guardian.testnet', blockHash,
      actions: [addFunctionCallKey(newKey.data, 'fam.sputnikv2.testnet', ['act_proposal'], nearToYocto('0.5'))],
    });
    const tx = transactions.createTransaction('guardian.testnet', kp.getPublicKey(), 'guardian.testnet', 7n,
      [transactions.addKey(newKey, transactions.functionCallAccessKey('fam.sputnikv2.testnet', ['act_proposal'], nearToYocto('0.5')))], blockHash);
    expect(Buffer.from(ours).toString('hex')).toBe(Buffer.from(transactions.encodeTransaction(tx)).toString('hex'));
  });

  it('signature verifies like near-api-js', () => {
    const signer = new Signer('operator.testnet', secret);
    const fields = { signerId: 'operator.testnet', publicKey: signer.publicKey, nonce: 1n, receiverId: 'x.testnet', blockHash, actions: [transfer(1n)] };
    const { signed, hash } = signTransaction(fields, signer);
    const sig = signed.slice(signed.length - 64);
    expect(kp.verify(hash, sig)).toBe(true);
    expect(signed[signed.length - 65]).toBe(0);
  });
});

describe('helpers', () => {
  it('amount conversions', () => {
    expect(nearToYocto('1')).toBe(10n ** 24n);
    expect(nearToYocto('0.000001')).toBe(10n ** 18n);
    expect(yoctoToNear(nearToYocto('12.3456'))).toBe(12.3456);
  });
  it('generated keys round-trip', () => {
    const k = generateKeyPair();
    const s = new Signer('a.testnet', k.secretKey);
    expect(s.publicKeyString).toBe(k.publicKey);
    expect(utils.KeyPair.fromString(k.secretKey as any).getPublicKey().toString()).toBe(k.publicKey);
  });
  it('base64 round-trip', () => {
    const b = new Uint8Array(70000).map((_, i) => i % 256);
    expect(fromBase64(toBase64(b))).toEqual(b);
  });
  it('parses outcomes and failures', () => {
    const ok = parseOutcome('h', { status: { SuccessValue: btoa('5') }, receipts_outcome: [] });
    expect(ok.value).toBe(5);
    expect(() => parseOutcome('h', { status: { SuccessValue: '' }, receipts_outcome: [{ outcome: { status: { Failure: { x: 1 } } } }] })).toThrow();
    expect(bs58.encode(new Uint8Array([1, 2]))).toBeTypeOf('string');
  });
});
