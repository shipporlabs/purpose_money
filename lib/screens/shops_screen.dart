import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../repo.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'add_shop_screen.dart';
import 'pay_screen.dart';

/// List of the family's shops. Used as a tab for parents and from the Family tab for siblings.
class ShopsScreen extends StatelessWidget {
  const ShopsScreen({super.key, required this.profile, required this.family, this.standalone = false});
  final Profile profile;
  final Family family;
  final bool standalone;

  @override
  Widget build(BuildContext context) {
    final body = StreamBuilder<List<Merchant>>(
      stream: Repo.instance.merchants(family.id),
      builder: (context, snap) {
        final shops = snap.data ?? [];
        return PageBody(children: [
          Row(children: [
            Expanded(child: Text('Shops', style: display(28))),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AddShopScreen(profile: profile, family: family))),
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
          ]),
          const SizedBox(height: 6),
          const Text('Shops, schools and landlords your family can pay.', style: TextStyle(color: Brand.muted)),
          const SizedBox(height: 14),
          if (snap.connectionState == ConnectionState.waiting && shops.isEmpty) const Center(child: CircularProgressIndicator()),
          if (snap.hasData && shops.isEmpty)
            const EmptyState(icon: Icons.storefront_outlined, title: 'No shops yet', body: 'Add the first shop you buy from. Your children approve it once.'),
          for (final m in shops)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(m.displayName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                      StatusChip(m.status),
                    ]),
                    const SizedBox(height: 4),
                    Text('${family.purpose(m.category)?.label ?? m.category} · ${m.bankName} ${m.maskedAccount}', style: const TextStyle(color: Brand.muted)),
                    Text('Bank name: ${m.accountName}', style: const TextStyle(color: Brand.muted, fontSize: 13)),
                    if (m.nameMatch < 0.5)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text('Bank name differs from the shop name, so the guardian will ask the family before paying.',
                            style: TextStyle(color: Brand.blue, fontSize: 13)),
                      ),
                    if (m.status == 'pending') ...[
                      const SizedBox(height: 8),
                      Text('${m.approvals.length} of ${m.approvalsNeeded} sibling approvals', style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (profile.isSibling && !m.approvals.contains(profile.uid) && !m.rejections.contains(profile.uid)) ...[
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(child: BusyButton(label: 'Decline', outlined: true, danger: true, onPressed: () => Api.instance.voteMerchant(family.id, m.id, false))),
                          const SizedBox(width: 10),
                          Expanded(child: BusyButton(label: 'Approve', onPressed: () => Api.instance.voteMerchant(family.id, m.id, true))),
                        ]),
                      ],
                    ],
                    if (m.approved) ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PayScreen(profile: profile, family: family, merchant: m))),
                        icon: const Icon(Icons.payments_outlined),
                        label: const Text('Pay this shop'),
                      ),
                    ],
                  ]),
                ),
              ),
            ),
        ]);
      },
    );
    return standalone ? Scaffold(appBar: AppBar(title: const Text('Shops')), body: body) : body;
  }
}
