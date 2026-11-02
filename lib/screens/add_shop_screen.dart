import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

class AddShopScreen extends StatefulWidget {
  const AddShopScreen({super.key, required this.profile, required this.family});
  final Profile profile;
  final Family family;
  @override
  State<AddShopScreen> createState() => _AddShopScreenState();
}

class _AddShopScreenState extends State<AddShopScreen> {
  final _name = TextEditingController();
  final _account = TextEditingController();
  Map<String, dynamic>? _bank;
  String? _verifiedName;
  late String _category = widget.family.purposes.isNotEmpty ? widget.family.purposes.first.key : '';
  List<Map<String, dynamic>>? _banks;
  Object? _banksError;

  @override
  void initState() {
    super.initState();
    _loadBanks();
  }

  Future<void> _loadBanks() async {
    try {
      final b = await Api.instance.banks();
      if (mounted) setState(() => _banks = b);
    } catch (e) {
      if (mounted) setState(() => _banksError = e);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _account.dispose();
    super.dispose();
  }

  Future<void> _pickBank() async {
    final banks = _banks;
    if (banks == null) return;
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _BankPicker(banks: banks),
    );
    if (picked != null) setState(() { _bank = picked; _verifiedName = null; });
  }

  Future<void> _verify() async {
    if (_bank == null) throw Exception('Choose the bank first.');
    if (_account.text.length != 10) throw Exception('Account numbers have 10 digits.');
    final name = await Api.instance.resolveAccount(_bank!['code'] as String, _account.text);
    setState(() => _verifiedName = name);
  }

  Future<void> _save() async {
    if (_verifiedName == null) await _verify();
    if (_name.text.trim().length < 2) throw Exception('Give the shop a name your family will recognise.');
    if (_category.isEmpty) throw Exception('Choose what this shop is for.');
    final res = await Api.instance.addMerchant({
      'familyId': widget.family.id,
      'displayName': _name.text.trim(),
      'category': _category,
      'bankCode': _bank!['code'],
      'bankName': _bank!['name'],
      'accountNumber': _account.text,
    });
    if (!mounted) return;
    final approved = res['status'] == 'approved';
    showInfo(context, approved ? 'Shop added and approved.' : 'Shop added. Your siblings have been asked to approve it.');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final needs = widget.family.approvalsNeeded;
    return Scaffold(
      appBar: AppBar(title: const Text('Add a shop')),
      body: PageBody(children: [
        const Text('Any shop, school or landlord with a Nigerian bank account can be paid. No app or terminal needed on their side.',
            style: TextStyle(color: Brand.muted, height: 1.45)),
        const SizedBox(height: 18),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Shop name', hintText: 'Mama Nkechi Stores'),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: _pickBank,
          borderRadius: BorderRadius.circular(14),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'Bank',
              suffixIcon: _banks == null && _banksError == null
                  ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                  : const Icon(Icons.expand_more),
              errorText: _banksError == null ? null : 'Couldn\'t load banks: $_banksError',
            ),
            child: Text(_bank?['name'] as String? ?? 'Choose bank', style: TextStyle(color: _bank == null ? Brand.muted : Brand.ink)),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _account,
          keyboardType: TextInputType.number,
          maxLength: 10,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Account number', counterText: ''),
          onChanged: (_) => setState(() => _verifiedName = null),
        ),
        const SizedBox(height: 10),
        if (_verifiedName == null)
          Align(alignment: Alignment.centerLeft, child: SizedBox(width: 200, child: BusyButton(label: 'Verify account', outlined: true, icon: Icons.verified_outlined, onPressed: _verify)))
        else
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Brand.mint, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              const Icon(Icons.verified, color: Brand.green),
              const SizedBox(width: 10),
              Expanded(child: Text('Bank says: $_verifiedName', style: const TextStyle(fontWeight: FontWeight.w800))),
            ]),
          ),
        const SizedBox(height: 18),
        const Text('What is it for?', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in widget.family.purposes)
            ChoiceChip(label: Text(p.label), selected: _category == p.key, onSelected: (_) => setState(() => _category = p.key)),
        ]),
        const SizedBox(height: 18),
        Text(
          widget.profile.isSibling && needs <= 1
              ? 'As a sibling, your approval is enough to activate this shop.'
              : 'It becomes payable once $needs sibling(s) approve it.',
          style: const TextStyle(color: Brand.muted),
        ),
        const SizedBox(height: 14),
        BusyButton(label: 'Add shop', icon: Icons.add_business_outlined, onPressed: _save),
      ]),
    );
  }
}

class _BankPicker extends StatefulWidget {
  const _BankPicker({required this.banks});
  final List<Map<String, dynamic>> banks;
  @override
  State<_BankPicker> createState() => _BankPickerState();
}

class _BankPickerState extends State<_BankPicker> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final list = widget.banks.where((b) => (b['name'] as String).toLowerCase().contains(_q.toLowerCase())).toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            autofocus: true,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search banks'),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) => ListTile(title: Text(list[i]['name'] as String), onTap: () => Navigator.of(context).pop(list[i])),
          ),
        ),
      ]),
    );
  }
}
