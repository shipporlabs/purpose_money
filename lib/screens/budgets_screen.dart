import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

class _Row {
  _Row(this.key, String label, int budget)
      : label = TextEditingController(text: label),
        budget = TextEditingController(text: '$budget');
  final String key;
  final TextEditingController label;
  final TextEditingController budget;
}

class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key, required this.family});
  final Family family;
  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  late final List<_Row> _rows = widget.family.purposes.map((p) => _Row(p.key, p.label, p.budgetNgn)).toList();

  @override
  void dispose() {
    for (final r in _rows) {
      r.label.dispose();
      r.budget.dispose();
    }
    super.dispose();
  }

  String _keyFor(String label) {
    var k = label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
    if (k.isEmpty || !RegExp(r'^[a-z]').hasMatch(k)) k = 'p_$k';
    if (k.length < 2) k = '${k}_x';
    return k.length > 20 ? k.substring(0, 20) : k;
  }

  Future<void> _save() async {
    final purposes = <String, dynamic>{};
    for (final r in _rows) {
      final label = r.label.text.trim();
      if (label.isEmpty) throw Exception('Every purpose needs a name.');
      final key = r.key.isNotEmpty ? r.key : _keyFor(label);
      if (purposes.containsKey(key)) throw Exception('Two purposes have the same name.');
      purposes[key] = {'label': label, 'budgetNgn': int.tryParse(r.budget.text) ?? 0};
    }
    if (purposes.isEmpty) throw Exception('Keep at least one purpose.');
    final res = await Api.instance.proposeChange(widget.family.id, 'budgets', {'purposes': purposes});
    if (!mounted) return;
    showInfo(context, res['status'] == 'applied' ? 'Budgets updated.' : 'Sent to your siblings for approval.');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final total = _rows.fold<int>(0, (s, r) => s + (int.tryParse(r.budget.text) ?? 0));
    return Scaffold(
      appBar: AppBar(title: const Text('Purposes and budgets')),
      body: PageBody(children: [
        Text('Monthly budget: ${naira(total)}', style: display(22)),
        const SizedBox(height: 6),
        Text('Changes need ${widget.family.approvalsNeeded} sibling approval(s).', style: const TextStyle(color: Brand.muted)),
        const SizedBox(height: 16),
        for (var i = 0; i < _rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Expanded(flex: 5, child: TextField(controller: _rows[i].label, decoration: const InputDecoration(labelText: 'Purpose'))),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: TextField(
                  controller: _rows[i].budget,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Budget', prefixText: '₦'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              IconButton(
                tooltip: 'Remove',
                onPressed: _rows.length <= 1 ? null : () => setState(() => _rows.removeAt(i)),
                icon: const Icon(Icons.close),
              ),
            ]),
          ),
        if (_rows.length < 8)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(onPressed: () => setState(() => _rows.add(_Row('', '', 0))), icon: const Icon(Icons.add), label: const Text('Add purpose')),
          ),
        const SizedBox(height: 16),
        BusyButton(label: 'Propose changes', onPressed: _save),
      ]),
    );
  }
}
