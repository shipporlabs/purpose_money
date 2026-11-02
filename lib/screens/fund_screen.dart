import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../repo.dart';
import '../theme.dart';
import '../widgets/common.dart';

class FundScreen extends StatefulWidget {
  const FundScreen({super.key, required this.profile, required this.family});
  final Profile profile;
  final Family family;
  @override
  State<FundScreen> createState() => _FundScreenState();
}

class _FundScreenState extends State<FundScreen> {
  Map<String, dynamic>? _info;
  Object? _error;
  int _method = 0; // 0 intents, 1 testnet
  int _usd = 25;
  String? _assetId;
  final _refund = TextEditingController();
  final _custom = TextEditingController();

  @override
  void initState() {
    super.initState();
    Api.instance.fundingTokens().then((v) {
      if (!mounted) return;
      setState(() {
        _info = v;
        final tokens = (v['tokens'] as List).cast<Map<String, dynamic>>();
        if (tokens.isNotEmpty) _assetId = tokens.first['assetId'] as String;
        if (v['intentsEnabled'] != true) _method = 1;
      });
    }).catchError((Object e) {
      if (mounted) setState(() { _error = e; _method = 1; });
    });
  }

  @override
  void dispose() {
    _refund.dispose();
    _custom.dispose();
    super.dispose();
  }

  int get _rate => (_info?['ngnPerUsd'] as num?)?.toInt() ?? 1500;
  int get _maxTestnet => (_info?['testnetTopupMaxUsd'] as num?)?.toInt() ?? 50;

  Future<void> _testnet() async {
    final usd = _usd.clamp(1, _maxTestnet);
    final res = await Api.instance.fundTestnet(widget.family.id, usd);
    if (!mounted) return;
    showInfo(context, 'Added ${naira((res['amountNgn'] as num?) ?? usd * _rate)} to the pot.');
    Navigator.of(context).pop();
  }

  Future<void> _intents() async {
    if (_assetId == null) throw Exception('Choose what you\'re sending.');
    if (_refund.text.trim().length < 8) throw Exception('Add a refund address on the same chain, in case the swap can\'t complete.');
    final res = await Api.instance.fundQuote(widget.family.id, _assetId!, _usd, _refund.text.trim());
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => DepositScreen(family: widget.family, contributionId: res['contributionId'] as String),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ((_info?['tokens'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final intentsOn = _info?['intentsEnabled'] == true;
    return Scaffold(
      appBar: AppBar(title: const Text('Add money')),
      body: PageBody(children: [
        Text('Fund the ${widget.family.name} pot', style: display(26)),
        const SizedBox(height: 6),
        Text('Money lands in your family\'s DAO on NEAR. 1 USD ≈ ${naira(_rate)} for budgeting.', style: const TextStyle(color: Brand.muted)),
        const SizedBox(height: 16),
        Wrap(spacing: 8, children: [
          ChoiceChip(label: const Text('From any chain (NEAR Intents)'), selected: _method == 0, onSelected: intentsOn ? (_) => setState(() => _method = 0) : null),
          ChoiceChip(label: const Text('Testnet top-up'), selected: _method == 1, onSelected: (_) => setState(() => _method = 1)),
        ]),
        if (_info != null && !intentsOn)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Cross-chain funding turns on once the server has a 1Click API key.', style: TextStyle(color: Brand.muted, fontSize: 13)),
          ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('$_error', style: const TextStyle(color: Brand.red))),
        const SizedBox(height: 18),
        const Text('Amount', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final v in const [10, 25, 50, 100, 200])
            if (_method == 0 || v <= _maxTestnet)
              ChoiceChip(label: Text('\$$v'), selected: _usd == v, onSelected: (_) => setState(() { _usd = v; _custom.clear(); })),
          SizedBox(
            width: 120,
            child: TextField(
              controller: _custom,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(hintText: 'Other', prefixText: '\$', isDense: true),
              onChanged: (v) => setState(() => _usd = int.tryParse(v) ?? _usd),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Text('≈ ${naira(_usd * _rate)} for the family', style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 20),
        if (_method == 0) ...[
          const Text('Send from', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final t in tokens)
              ChoiceChip(
                label: Text('${t['symbol']} · ${t['blockchain']}'),
                selected: _assetId == t['assetId'],
                onSelected: (_) => setState(() => _assetId = t['assetId'] as String),
              ),
          ]),
          const SizedBox(height: 14),
          TextField(
            controller: _refund,
            decoration: const InputDecoration(labelText: 'Your refund address on that chain', helperText: 'Used only if the swap can\'t complete.'),
          ),
          const SizedBox(height: 18),
          BusyButton(label: 'Get deposit address', icon: Icons.swap_horiz, onPressed: _intents),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Brand.amberSoft, borderRadius: BorderRadius.circular(14)),
            child: Text(
              'Testnet top-up sends free test NEAR to your family DAO so you can try payments end to end. Up to \$$_maxTestnet per top-up.',
              style: const TextStyle(height: 1.4),
            ),
          ),
          const SizedBox(height: 18),
          BusyButton(label: 'Add ${naira(_usd.clamp(1, _maxTestnet) * _rate)} (test)', icon: Icons.science_outlined, onPressed: _testnet),
        ],
      ]),
    );
  }
}

/// Shows the 1Click deposit address and follows the swap until the pot is credited.
class DepositScreen extends StatefulWidget {
  const DepositScreen({super.key, required this.family, required this.contributionId});
  final Family family;
  final String contributionId;
  @override
  State<DepositScreen> createState() => _DepositScreenState();
}

class _DepositScreenState extends State<DepositScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _poll());
  }

  Future<void> _poll() async {
    try {
      final r = await Api.instance.fundStatus(widget.family.id, widget.contributionId);
      final s = r['status'];
      if (s == 'credited' || s == 'refunded' || s == 'failed' || s == 'credit_failed') _timer?.cancel();
    } catch (_) {/* keep polling */}
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Send your deposit')),
      body: StreamBuilder<Contribution?>(
        stream: Repo.instance.contribution(widget.family.id, widget.contributionId),
        builder: (context, snap) {
          final c = snap.data;
          if (c == null) return const Center(child: CircularProgressIndicator());
          final done = c.status == 'credited';
          return PageBody(children: [
            Row(children: [Expanded(child: Text(done ? 'Money is in the pot' : 'Send exactly', style: display(24))), StatusChip(c.status)]),
            const SizedBox(height: 10),
            if (!done) ...[
              Text('${c.amountIn} ${c.originSymbol}', style: display(34)),
              Text('on ${c.originChain}', style: const TextStyle(color: Brand.muted, fontWeight: FontWeight.w700)),
              const SizedBox(height: 18),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: Brand.line)),
                  child: QrImageView(data: c.depositAddress, size: 200),
                ),
              ),
              const SizedBox(height: 14),
              SelectableText(c.depositAddress, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
              if (c.depositMemo != null) ...[
                const SizedBox(height: 6),
                SelectableText('Memo: ${c.depositMemo}', textAlign: TextAlign.center, style: const TextStyle(color: Brand.red, fontWeight: FontWeight.w800)),
              ],
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: c.depositAddress));
                  if (context.mounted) showInfo(context, 'Address copied');
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy address'),
              ),
              const SizedBox(height: 14),
              const Text(
                'NEAR Intents swaps it to USDC and settles it. We check every few seconds and credit your family pot when it lands. The address expires if unused.',
                style: TextStyle(color: Brand.muted, height: 1.45),
              ),
            ] else ...[
              Text('${naira(c.amountNgn)} was added to ${widget.family.name}.', style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 14),
              if (c.mirrorUrl != null) OutlinedButton(onPressed: () => openUrl(c.mirrorUrl), child: const Text('View the DAO deposit')),
              const SizedBox(height: 10),
              FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
            ],
            if (c.error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(c.error!, style: const TextStyle(color: Brand.red))),
          ]);
        },
      ),
    );
  }
}
