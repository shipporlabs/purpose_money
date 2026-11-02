import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../repo.dart';
import '../theme.dart';
import '../widgets/common.dart';

class PaymentDetailScreen extends StatelessWidget {
  const PaymentDetailScreen({super.key, required this.profile, required this.family, required this.paymentId, this.justRequested = false});
  final Profile profile;
  final Family family;
  final String paymentId;
  final bool justRequested;

  String _headline(Payment p) {
    switch (p.status) {
      case 'approved':
      case 'paying':
        return 'Approved — paying the shop…';
      case 'paid':
        return 'Paid';
      case 'escalated':
        return 'Waiting for the family';
      case 'blocked':
        return 'Blocked by the guardian';
      case 'rejected':
        return 'The family said no';
      case 'payout_failed':
        return 'Approved, but the bank payout failed';
      case 'failed':
        return 'Couldn\'t complete';
      default:
        return p.status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payment')),
      body: StreamBuilder<Payment?>(
        stream: Repo.instance.payment(family.id, paymentId),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final p = snap.data!;
          final canVote = profile.isSibling && p.status == 'escalated' && !p.approvals.contains(profile.uid) && !p.rejections.contains(profile.uid);
          final (_, bg, fg) = StatusChip.styleFor(p.status);
          return PageBody(children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(22)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  if (p.status == 'approved' || p.status == 'paying')
                    SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: fg))
                  else
                    Icon(
                      p.status == 'paid' ? Icons.check_circle : p.status == 'escalated' ? Icons.how_to_vote : Icons.block,
                      color: fg,
                    ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_headline(p), style: TextStyle(fontWeight: FontWeight.w800, color: fg, fontSize: 16))),
                ]),
                const SizedBox(height: 14),
                Text(naira(p.amountNgn), style: display(36)),
                const SizedBox(height: 4),
                Text('${p.merchantName} · ${p.purposeLabel}', style: const TextStyle(fontWeight: FontWeight.w700)),
                if (p.note.isNotEmpty) Text('"${p.note}"', style: const TextStyle(color: Brand.muted)),
                const SizedBox(height: 10),
                Text(p.reason, style: const TextStyle(height: 1.4)),
                if (p.aiNote != null) ...[
                  const SizedBox(height: 10),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.auto_awesome, size: 16, color: Brand.green),
                    const SizedBox(width: 6),
                    Expanded(child: Text(p.aiNote!, style: const TextStyle(fontStyle: FontStyle.italic, height: 1.4))),
                  ]),
                ],
                if (p.error != null && (p.status == 'failed' || p.status == 'payout_failed')) ...[
                  const SizedBox(height: 10),
                  Text(p.error!, style: const TextStyle(color: Brand.red, fontSize: 13)),
                ],
              ]),
            ),
            if (p.status == 'escalated') ...[
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${p.approvals.length} of ${p.approvalsNeeded} sibling approvals', style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(
                      [
                        ...p.approvals.map((u) => '✓ ${family.nameOf(u)}'),
                        ...p.rejections.map((u) => '✗ ${family.nameOf(u)}'),
                      ].join('   '),
                      style: const TextStyle(color: Brand.muted),
                    ),
                    if (canVote) ...[
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(child: BusyButton(label: 'Decline', outlined: true, danger: true, onPressed: () => Api.instance.votePayment(family.id, p.id, false))),
                        const SizedBox(width: 10),
                        Expanded(child: BusyButton(label: 'Approve', icon: Icons.check, onPressed: () => Api.instance.votePayment(family.id, p.id, true))),
                      ]),
                    ] else if (profile.isParent)
                      const Padding(padding: EdgeInsets.only(top: 8), child: Text('Your children have been asked to approve this.')),
                  ]),
                ),
              ),
            ],
            if (p.status == 'payout_failed' && profile.isSibling) ...[
              const SizedBox(height: 12),
              BusyButton(label: 'Retry bank payout', icon: Icons.refresh, onPressed: () => Api.instance.retryPayout(family.id, p.id)),
            ],
            SectionTitle('Guardian checks'),
            Card(
              child: Column(children: [
                for (final c in p.checks)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      c.passed ? Icons.check_circle : (c.severity == 'block' ? Icons.cancel : Icons.flag),
                      color: c.passed ? Brand.green : (c.severity == 'block' ? Brand.red : Brand.blue),
                    ),
                    title: Text(c.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(c.detail),
                  ),
              ]),
            ),
            SectionTitle('Receipt'),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Column(children: [
                  InfoRow('Requested by', p.requestedByName),
                  InfoRow('When', p.createdAt == null ? '' : '${p.createdAt}'.split('.').first),
                  InfoRow('Paid to', '${p.accountName} (${p.merchantName})'),
                  if (p.onchain['daoId'] != null) InfoRow('Family DAO', shortAccount('${p.onchain['daoId']}')),
                  if (p.onchain['proposalId'] != null) InfoRow('DAO proposal', '#${p.onchain['proposalId']} · ${p.onchain['amountNear']} NEAR'),
                  if (p.onchain['proposeUrl'] != null) InfoRow('Proposal tx', 'View on NearBlocks', onTap: () => openUrl(p.onchain['proposeUrl'] as String)),
                  if (p.onchain['approveUrl'] != null)
                    InfoRow('Approved by', '${p.onchain['approvedBy']} · view tx', onTap: () => openUrl(p.onchain['approveUrl'] as String)),
                  if (p.paystack['reference'] != null) InfoRow('Bank transfer', '${p.paystack['reference']}'),
                  if (p.paystack['testMode'] == true) const InfoRow('Paystack', 'Test mode (no real naira moved)'),
                ]),
              ),
            ),
          ]);
        },
      ),
    );
  }
}
