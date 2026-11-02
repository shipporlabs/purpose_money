import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/brand_mark.dart';
import '../widgets/common.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.profile});
  final Profile profile;
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _mode = 0; // 0 = start, 1 = join
  String _role = 'sibling';
  final _familyName = TextEditingController();
  final _code = TextEditingController();

  @override
  void dispose() {
    _familyName.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final name = _familyName.text.trim();
    if (name.length < 2) throw Exception('Give your family pot a name, like "Okonkwo Family".');
    await Api.instance.createFamily(name);
  }

  Future<void> _join() async {
    final code = _code.text.trim().toUpperCase();
    if (code.length != 6) throw Exception('Invite codes have 6 characters.');
    await Api.instance.joinFamily(code, _role);
  }

  Widget _option(int index, IconData icon, String title, String body) {
    final selected = _mode == index;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => setState(() => _mode = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? Brand.green : Brand.line, width: selected ? 2 : 1),
        ),
        child: Row(children: [
          CircleAvatar(backgroundColor: selected ? Brand.deep : Brand.mint, child: Icon(icon, color: selected ? Colors.white : Brand.green)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 2),
              Text(body, style: const TextStyle(color: Brand.muted, height: 1.4)),
            ]),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const BrandMark(size: 26),
        actions: [TextButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text('Sign out'))],
      ),
      body: PageBody(children: [
        const SizedBox(height: 8),
        Text('Hi ${widget.profile.displayName.split(' ').first}, let\'s set up your family pot.', style: display(28)),
        const SizedBox(height: 20),
        _option(0, Icons.add_home_outlined, 'Start a family pot', 'For a sibling abroad. You\'ll get a code to invite your siblings and parents.'),
        const SizedBox(height: 10),
        _option(1, Icons.group_add_outlined, 'Join with an invite code', 'Your sibling already started one. Join as a sibling or as a parent.'),
        const SizedBox(height: 24),
        if (_mode == 0) ...[
          TextField(
            controller: _familyName,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Family pot name', hintText: 'Okonkwo Family'),
          ),
          const SizedBox(height: 10),
          const Text(
            'We\'ll create your family\'s own DAO on NEAR testnet. It takes about half a minute; you can keep going while it finishes.',
            style: TextStyle(color: Brand.muted, height: 1.45),
          ),
          const SizedBox(height: 18),
          BusyButton(label: 'Create family pot', icon: Icons.arrow_forward, onPressed: _start),
        ] else ...[
          TextField(
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            maxLength: 6,
            decoration: const InputDecoration(labelText: 'Invite code', hintText: 'K7Q2MX', counterText: ''),
          ),
          const SizedBox(height: 14),
          const Text('I am joining as', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            ChoiceChip(
              label: const Text('A sibling (I fund the pot)'),
              selected: _role == 'sibling',
              onSelected: (_) => setState(() => _role = 'sibling'),
            ),
            ChoiceChip(
              label: const Text('A parent (I spend from it)'),
              selected: _role == 'parent',
              onSelected: (_) => setState(() => _role = 'parent'),
            ),
          ]),
          const SizedBox(height: 18),
          BusyButton(label: 'Join family', icon: Icons.arrow_forward, onPressed: _join),
        ],
      ]),
    );
  }
}
