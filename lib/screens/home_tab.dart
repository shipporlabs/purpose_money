import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../repo.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'fund_screen.dart';
import 'pay_screen.dart';
import 'payment_detail_screen.dart';

class HomeTab extends StatelessWidget {
  const HomeTab({super.key, required this.profile, required this.family});
  final Profile profile;
  final Family family;

  @override
  Widget build(BuildContext context) {
    final first = profile.displayName.split(' ').first;
    return PageBody(children: [
      Text(profile.isParent ? 'Hi $first' : family.name, style: display(28)),
      const SizedBox(height: 4),
      Text(
        profile.isParent ? 'From ${family.siblingUids.length} of your children abroad' : '${family.siblingUids.length} sibling(s) · ${family.parentUids.length} parent(s)',
        style: const TextStyle(color: Brand.muted),
      ),
      const SizedBox(height: 16),
      if (family.daoStatus != 'active') _DaoBanner(family: family, isSibling: profile.isSibling),
      _BalanceCard(family: family),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PayScreen(profile: profile, family: family))),
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Pay a shop'),
          ),
        ),
        if (profile.isSibling) ...[
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => FundScreen(profile: profile, family: family))),
              icon: const Icon(Icons.add),
              label: const Text('Add money'),
            ),
          ),
        ],
      ]),
      SectionTitle('Purposes this month'),
      if (family.purposes.isEmpty)
        const EmptyState(icon: Icons.category_outlined, title: 'No purposes yet', body: 'A sibling can add food, rent or school budgets from the Family tab.')
      else
        ...family.purposes.map((p) => Padding(padding: const EdgeInsets.only(bottom: 10), child: PurposeBar(p))),
      if (profile.isSibling) ...[
        SectionTitle('Who funded the pot'),
        Card(
          child: Column(children: [
            for (final uid in family.siblingUids)
              ListTile(
                leading: CircleAvatar(backgroundColor: Brand.mint, child: Text(initial(family.nameOf(uid)))),
                title: Text(uid == profile.uid ? '${family.nameOf(uid)} (you)' : family.nameOf(uid), style: const TextStyle(fontWeight: FontWeight.w700)),
                trailing: Text(naira(family.contributedNgn[uid] ?? 0), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
          ]),
        ),
      ],
      SectionTitle('Recent payments'),
      StreamBuilder<List<Payment>>(
        stream: Repo.instance.payments(family.id, limit: 5),
        builder: (context, snap) {
          final list = snap.data ?? [];
          if (snap.connectionState == ConnectionState.waiting && list.isEmpty) return const Center(child: CircularProgressIndicator());
          if (list.isEmpty) {
            return const EmptyState(icon: Icons.receipt_long_outlined, title: 'No payments yet', body: 'Payments to shops appear here with their receipts.');
          }
          return Card(
            child: Column(children: [
              for (final p in list)
                PaymentTile(p, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PaymentDetailScreen(profile: profile, family: family, paymentId: p.id)))),
            ]),
          );
        },
      ),
    ]);
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.family});
  final Family family;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Brand.deep, borderRadius: BorderRadius.circular(22)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Available in the pot', style: TextStyle(color: Color(0xFFC9DBD1), fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(naira(family.balanceNgn), style: display(38, color: Colors.white)),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.shield_outlined, color: Brand.accent, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                family.daoStatus == 'active' ? 'Locked to your purposes · checked by the guardian' : 'Setting up on NEAR…',
                style: const TextStyle(color: Color(0xFFC9DBD1), fontSize: 13),
              ),
            ),
          ]),
        ]),
      );
}

class _DaoBanner extends StatelessWidget {
  const _DaoBanner({required this.family, required this.isSibling});
  final Family family;
  final bool isSibling;
  @override
  Widget build(BuildContext context) {
    final failed = family.daoStatus == 'failed';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: failed ? Brand.redSoft : Brand.amberSoft, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (!failed) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          if (failed) const Icon(Icons.error_outline, color: Brand.red),
          const SizedBox(width: 10),
          Expanded(
            child: Text(failed ? 'We couldn\'t create your family DAO on NEAR' : 'Creating your family DAO on NEAR testnet…',
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ]),
        if (failed && family.daoError != null) ...[
          const SizedBox(height: 6),
          Text(family.daoError!, style: const TextStyle(fontSize: 12, color: Brand.muted)),
        ],
        if (failed && isSibling) ...[
          const SizedBox(height: 10),
          BusyButton(label: 'Try again', outlined: true, onPressed: () => Api.instance.retryDao(family.id)),
        ],
      ]),
    );
  }
}
