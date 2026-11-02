import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../repo.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'add_shop_screen.dart';
import 'payment_detail_screen.dart';

class PayScreen extends StatefulWidget {
  const PayScreen({super.key, required this.profile, required this.family, this.merchant});
  final Profile profile;
  final Family family;
  final Merchant? merchant;
  @override
  State<PayScreen> createState() => _PayScreenState();
}

class _PayScreenState extends State<PayScreen> {
  Merchant? _merchant;
  final _amount = TextEditingController();
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _merchant = widget.merchant;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final m = _merchant;
    if (m == null) throw Exception('Choose a shop to pay.');
    final amount = int.tryParse(_amount.text.replaceAll(',', '').trim()) ?? 0;
    if (amount < 100) throw Exception('Enter an amount of at least ₦100.');
    final res = await Api.instance.requestPayment(widget.family.id, m.id, amount, _note.text.trim());
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => PaymentDetailScreen(profile: widget.profile, family: widget.family, paymentId: res['paymentId'] as String, justRequested: true),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final purpose = _merchant == null ? null : widget.family.purpose(_merchant!.category);
    return Scaffold(
      appBar: AppBar(title: const Text('Pay a shop')),
      body: StreamBuilder<List<Merchant>>(
        stream: Repo.instance.merchants(widget.family.id),
        builder: (context, snap) {
          final shops = (snap.data ?? []).where((m) => m.status != 'rejected').toList();
          return PageBody(children: [
            const Text('Which shop?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 10),
            if (snap.connectionState == ConnectionState.waiting && shops.isEmpty) const Center(child: CircularProgressIndicator()),
            if (snap.hasData && shops.isEmpty)
              const EmptyState(icon: Icons.storefront_outlined, title: 'No shops yet', body: 'Add the shop, school or landlord you pay. The family approves it once.'),
            ...shops.map((m) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => setState(() => _merchant = m),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _merchant?.id == m.id ? Brand.green : Brand.line, width: _merchant?.id == m.id ? 2 : 1),
                      ),
                      child: Row(children: [
                        Icon(Icons.storefront_outlined, color: PurposeBar.colorFor(m.category) == Brand.accent ? const Color(0xFF7A4F00) : PurposeBar.colorFor(m.category)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(m.displayName, style: const TextStyle(fontWeight: FontWeight.w800)),
                            Text('${widget.family.purpose(m.category)?.label ?? m.category} · ${m.bankName} ${m.maskedAccount}',
                                style: const TextStyle(color: Brand.muted, fontSize: 13)),
                          ]),
                        ),
                        if (!m.approved) const StatusChip('pending'),
                      ]),
                    ),
                  ),
                )),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AddShopScreen(profile: widget.profile, family: widget.family))),
                icon: const Icon(Icons.add),
                label: const Text('Add a shop'),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: display(26),
              decoration: const InputDecoration(labelText: 'Amount (₦)', prefixText: '₦ '),
              onChanged: (_) => setState(() {}),
            ),
            if (purpose != null) ...[
              const SizedBox(height: 8),
              Text('${naira(purpose.remainingNgn)} left in ${purpose.label}', style: const TextStyle(color: Brand.muted)),
            ],
            const SizedBox(height: 12),
            TextField(controller: _note, maxLength: 120, decoration: const InputDecoration(labelText: 'Note (optional)', hintText: 'Groceries for the week')),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Brand.mint, borderRadius: BorderRadius.circular(14)),
              child: const Row(children: [
                Icon(Icons.shield_outlined, color: Brand.green),
                SizedBox(width: 10),
                Expanded(child: Text('The guardian checks this payment against your family\'s rules before any money moves.', style: TextStyle(height: 1.4))),
              ]),
            ),
            const SizedBox(height: 16),
            BusyButton(label: 'Request payment', icon: Icons.send_outlined, onPressed: _submit),
          ]);
        },
      ),
    );
  }
}
