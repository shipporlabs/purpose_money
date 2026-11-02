import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import '../repo.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'payment_detail_screen.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key, required this.profile, required this.family});
  final Profile profile;
  final Family family;
  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  int _view = 0; // 0 payments, 1 money in

  @override
  Widget build(BuildContext context) {
    final family = widget.family;
    return PageBody(children: [
      Text('Activity', style: display(28)),
      const SizedBox(height: 12),
      Wrap(spacing: 8, children: [
        ChoiceChip(label: const Text('Payments'), selected: _view == 0, onSelected: (_) => setState(() => _view = 0)),
        ChoiceChip(label: const Text('Money in'), selected: _view == 1, onSelected: (_) => setState(() => _view = 1)),
      ]),
      const SizedBox(height: 12),
      if (_view == 0)
        StreamBuilder<List<Payment>>(
          stream: Repo.instance.payments(family.id, limit: 100),
          builder: (context, snap) {
            final list = snap.data ?? [];
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            if (list.isEmpty) return const EmptyState(icon: Icons.receipt_long_outlined, title: 'No payments yet');
            return Card(
              child: Column(children: [
                for (final p in list)
                  PaymentTile(p,
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => PaymentDetailScreen(profile: widget.profile, family: family, paymentId: p.id)))),
              ]),
            );
          },
        )
      else
        StreamBuilder<List<Contribution>>(
          stream: Repo.instance.contributions(family.id, limit: 100),
          builder: (context, snap) {
            final list = snap.data ?? [];
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            if (list.isEmpty) return const EmptyState(icon: Icons.savings_outlined, title: 'No money in yet', body: 'Siblings add money from the Pot tab.');
            return Card(
              child: Column(children: [
                for (final c in list)
                  ListTile(
                    onTap: c.mirrorUrl == null ? null : () => openUrl(c.mirrorUrl),
                    leading: CircleAvatar(
                      backgroundColor: Brand.mint,
                      child: Icon(c.method == 'intents' ? Icons.swap_horiz : Icons.science_outlined, color: Brand.green),
                    ),
                    title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(
                      c.method == 'intents'
                          ? 'NEAR Intents · ${c.amountIn} ${c.originSymbol} on ${c.originChain} · ${timeAgo(c.createdAt)}'
                          : 'Testnet top-up · ${timeAgo(c.createdAt)}',
                    ),
                    trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(c.amountNgn > 0 ? naira(c.amountNgn) : '\$${c.amountUsd}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      StatusChip(c.status),
                    ]),
                  ),
              ]),
            );
          },
        ),
    ]);
  }
}
