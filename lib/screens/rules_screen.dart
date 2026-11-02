import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

class RulesScreen extends StatefulWidget {
  const RulesScreen({super.key, required this.family});
  final Family family;
  @override
  State<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends State<RulesScreen> {
  late final Rules r = widget.family.rules;
  late final _auto = TextEditingController(text: '${r.autoApproveLimitNgn}');
  late final _cap = TextEditingController(text: '${r.dailyCapPerMerchantNgn}');
  late final _cool = TextEditingController(text: '${r.newMerchantCooldownHours}');
  late final _count = TextEditingController(text: '${r.maxPaymentsPerDay}');
  late final _approvals = TextEditingController(text: '${r.siblingApprovalsRequired}');

  @override
  void dispose() {
    for (final c in [_auto, _cap, _cool, _count, _approvals]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _field(TextEditingController c, String label, String help, {String? prefix}) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: label, helperText: help, prefixText: prefix, helperMaxLines: 2),
        ),
      );

  Future<void> _save() async {
    int v(TextEditingController c) => int.tryParse(c.text) ?? 0;
    final res = await Api.instance.proposeChange(widget.family.id, 'rules', {
      'rules': {
        'autoApproveLimitNgn': v(_auto),
        'dailyCapPerMerchantNgn': v(_cap),
        'newMerchantCooldownHours': v(_cool),
        'maxPaymentsPerDay': v(_count).clamp(1, 100),
        'siblingApprovalsRequired': v(_approvals).clamp(1, 10),
      }
    });
    if (!mounted) return;
    showInfo(context, res['status'] == 'applied' ? 'Rules updated.' : 'Sent to your siblings for approval.');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Guardian rules')),
      body: PageBody(children: [
        Text('The guardian approves payments that pass every rule and asks you about the rest.', style: display(20, weight: FontWeight.w700)),
        const SizedBox(height: 18),
        _field(_auto, 'Auto-approve limit', 'Payments up to this amount go through without asking.', prefix: '₦'),
        _field(_cap, 'Daily cap per shop', 'Total a single shop can receive in one day before the family is asked.', prefix: '₦'),
        _field(_cool, 'New-shop cooling-off (hours)', 'Ask the family before paying a newly approved shop within this window. 0 turns it off.'),
        _field(_count, 'Payments per day', 'More than this in a day gets flagged.'),
        _field(_approvals, 'Sibling approvals needed', 'For flagged payments, new shops and rule changes (capped at the number of siblings).'),
        const SizedBox(height: 6),
        const Text('Hard limits always apply: unapproved shops, empty budgets and an empty pot are blocked outright.',
            style: TextStyle(color: Brand.muted, height: 1.4)),
        const SizedBox(height: 16),
        BusyButton(label: 'Propose new rules', onPressed: _save),
      ]),
    );
  }
}
