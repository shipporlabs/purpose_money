import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../repo.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'payment_detail_screen.dart';

class ApprovalsScreen extends StatelessWidget {
  const ApprovalsScreen({super.key, required this.profile, required this.family});
  final Profile profile;
  final Family family;

  bool _mine(List<String> a, List<String> r) => !a.contains(profile.uid) && !r.contains(profile.uid);

  Widget _voteRow(Future<void> Function(bool) vote) => Row(children: [
        Expanded(child: BusyButton(label: 'Decline', outlined: true, danger: true, onPressed: () => vote(false))),
        const SizedBox(width: 10),
        Expanded(child: BusyButton(label: 'Approve', icon: Icons.check, onPressed: () => vote(true))),
      ]);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Payment>>(
      stream: Repo.instance.payments(family.id, limit: 30),
      builder: (context, ps) => StreamBuilder<List<Merchant>>(
        stream: Repo.instance.merchants(family.id),
        builder: (context, ms) => StreamBuilder<List<Change>>(
          stream: Repo.instance.changes(family.id),
          builder: (context, cs) {
            final payments = (ps.data ?? []).where((p) => p.status == 'escalated').toList();
            final shops = (ms.data ?? []).where((m) => m.status == 'pending').toList();
            final changes = (cs.data ?? []).where((c) => c.status == 'pending').toList();
            final nothing = payments.isEmpty && shops.isEmpty && changes.isEmpty;
            return PageBody(children: [
              Text('Approvals', style: display(28)),
              const SizedBox(height: 6),
              Text('Anything outside the family rules waits here for ${family.approvalsNeeded} sibling approval(s).', style: const TextStyle(color: Brand.muted)),
              const SizedBox(height: 10),
              if (nothing)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: EmptyState(icon: Icons.verified_user_outlined, title: 'All clear', body: 'The guardian is handling everything within your rules.'),
                ),
              if (payments.isNotEmpty) SectionTitle('Payments flagged by the guardian'),
              for (final p in payments)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        InkWell(
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PaymentDetailScreen(profile: profile, family: family, paymentId: p.id))),
                          child: Row(children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(naira(p.amountNgn), style: display(24)),
                                Text('${p.merchantName} · ${p.purposeLabel}', style: const TextStyle(fontWeight: FontWeight.w700)),
                                Text('Requested by ${p.requestedByName} · ${timeAgo(p.createdAt)}', style: const TextStyle(color: Brand.muted, fontSize: 13)),
                              ]),
                            ),
                            const Icon(Icons.chevron_right),
                          ]),
                        ),
                        const SizedBox(height: 8),
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Icon(Icons.flag, color: Brand.blue, size: 18),
                          const SizedBox(width: 6),
                          Expanded(child: Text(p.reason)),
                        ]),
                        const SizedBox(height: 8),
                        Text('${p.approvals.length} of ${p.approvalsNeeded} approvals', style: const TextStyle(color: Brand.muted)),
                        if (_mine(p.approvals, p.rejections)) ...[
                          const SizedBox(height: 10),
                          _voteRow((ok) => Api.instance.votePayment(family.id, p.id, ok)),
                        ],
                      ]),
                    ),
                  ),
                ),
              if (shops.isNotEmpty) SectionTitle('New shops'),
              for (final m in shops)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(m.displayName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        Text('${family.purpose(m.category)?.label ?? m.category} · added by ${m.addedByName}', style: const TextStyle(color: Brand.muted)),
                        const SizedBox(height: 6),
                        Row(children: [
                          Icon(m.nameMatch >= 0.5 ? Icons.verified : Icons.warning_amber, size: 18, color: m.nameMatch >= 0.5 ? Brand.green : Brand.blue),
                          const SizedBox(width: 6),
                          Expanded(child: Text('Bank account: ${m.accountName} · ${m.bankName} ${m.maskedAccount}')),
                        ]),
                        const SizedBox(height: 6),
                        Text('${m.approvals.length} of ${m.approvalsNeeded} approvals', style: const TextStyle(color: Brand.muted)),
                        if (_mine(m.approvals, m.rejections)) ...[
                          const SizedBox(height: 10),
                          _voteRow((ok) => Api.instance.voteMerchant(family.id, m.id, ok)),
                        ],
                      ]),
                    ),
                  ),
                ),
              if (changes.isNotEmpty) SectionTitle('Budget and rule changes'),
              for (final c in changes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(c.summary, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.4)),
                        const SizedBox(height: 4),
                        Text('Proposed by ${c.proposedByName} · ${c.approvals.length} of ${c.approvalsNeeded} approvals', style: const TextStyle(color: Brand.muted)),
                        if (_mine(c.approvals, c.rejections)) ...[
                          const SizedBox(height: 10),
                          _voteRow((ok) => Api.instance.voteChange(family.id, c.id, ok)),
                        ],
                      ]),
                    ),
                  ),
                ),
            ]);
          },
        ),
      ),
    );
  }
}
