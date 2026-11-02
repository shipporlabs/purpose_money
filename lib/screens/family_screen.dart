import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'budgets_screen.dart';
import 'rules_screen.dart';
import 'shops_screen.dart';

class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key, required this.profile, required this.family});
  final Profile profile;
  final Family family;
  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  Future<Map<String, dynamic>>? _chain;

  @override
  void initState() {
    super.initState();
    _chain = Api.instance.chainInfo(widget.family.id);
  }

  @override
  void didUpdateWidget(covariant FamilyScreen old) {
    super.didUpdateWidget(old);
    if (old.family.daoStatus != widget.family.daoStatus || old.family.balanceNgn != widget.family.balanceNgn) {
      _chain = Api.instance.chainInfo(widget.family.id);
    }
  }

  Future<void> _newMonth() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Start a new month?'),
        content: const Text('This resets what each purpose has spent so budgets refill. Money already in the pot stays.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Propose')),
        ],
      ),
    );
    if (ok != true) return;
    final r = await Api.instance.proposeChange(widget.family.id, 'new_month', {});
    if (mounted) showInfo(context, r['status'] == 'applied' ? 'New month started.' : 'Sent to your siblings for approval.');
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.family;
    final p = widget.profile;
    final r = f.rules;
    return PageBody(children: [
      Text(f.name, style: display(28)),
      const SizedBox(height: 4),
      Text('You are a ${p.role} in this family', style: const TextStyle(color: Brand.muted)),
      SectionTitle('Invite your family'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Invite code', style: TextStyle(color: Brand.muted, fontWeight: FontWeight.w600)),
                Text(f.inviteCode, style: display(30).copyWith(letterSpacing: 4)),
                const Text('Siblings and parents enter this after signing up.', style: TextStyle(color: Brand.muted, fontSize: 13)),
              ]),
            ),
            IconButton.filledTonal(
              tooltip: 'Copy invite',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(
                    text: 'Join our family pot "${f.name}" on Purpose Money. Sign up, choose "Join with an invite code" and enter ${f.inviteCode}.'));
                if (context.mounted) showInfo(context, 'Invite copied');
              },
              icon: const Icon(Icons.copy),
            ),
          ]),
        ),
      ),
      SectionTitle('Members'),
      Card(
        child: Column(children: [
          for (final uid in [...f.siblingUids, ...f.parentUids])
            ListTile(
              leading: CircleAvatar(
                backgroundColor: f.parentUids.contains(uid) ? Brand.amberSoft : Brand.mint,
                child: Icon(f.parentUids.contains(uid) ? Icons.elderly : Icons.flight_takeoff, color: Brand.ink, size: 20),
              ),
              title: Text(uid == p.uid ? '${f.nameOf(uid)} (you)' : f.nameOf(uid), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(f.parentUids.contains(uid) ? 'Parent · spends from the pot' : 'Sibling · funds and approves'),
            ),
        ]),
      ),
      if (p.isSibling) ...[
        SectionTitle('Budgets and rules'),
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.category_outlined),
              title: const Text('Purposes and budgets', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${f.purposes.length} purposes · ${naira(f.totalBudget)} a month'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BudgetsScreen(family: f))),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: const Text('Guardian rules', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('Auto-approve up to ${naira(r.autoApproveLimitNgn)} · ${r.siblingApprovalsRequired} sibling approval(s) for the rest'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RulesScreen(family: f))),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: const Text('Shops', style: TextStyle(fontWeight: FontWeight.w700)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShopsScreen(profile: p, family: f, standalone: true))),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.restart_alt),
              title: const Text('Start a new month', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Refill every purpose budget'),
              onTap: () => _newMonth().catchError((Object e) => showError(context, e)),
            ),
          ]),
        ),
      ] else ...[
        SectionTitle('Guardian rules'),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Column(children: [
              InfoRow('Auto-approved up to', naira(r.autoApproveLimitNgn)),
              InfoRow('Per-shop daily cap', naira(r.dailyCapPerMerchantNgn)),
              InfoRow('Payments per day', '${r.maxPaymentsPerDay}'),
            ]),
          ),
        ),
      ],
      SectionTitle('On NEAR'),
      Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: FutureBuilder<Map<String, dynamic>>(
            future: _chain,
            builder: (context, snap) {
              if (snap.hasError) return Padding(padding: const EdgeInsets.all(8), child: Text('Couldn\'t reach NEAR: ${snap.error}'));
              final c = snap.data;
              return Column(children: [
                InfoRow('Network', f.network),
                InfoRow('Family DAO', shortAccount(f.daoId), onTap: c == null ? null : () => openUrl(c['explorer'] as String?)),
                InfoRow('Status', f.daoStatus == 'active' ? 'Live' : f.daoStatus),
                if (c != null) ...[
                  InfoRow('DAO balance', '${c['balanceNear']} NEAR (${c['spendableNear']} spendable)'),
                  InfoRow('Proposals so far', '${c['lastProposalId'] ?? 0}'),
                  for (final role in (c['roles'] as List? ?? const []))
                    InfoRow('Role: ${role['name']}', '${(role['members'] as List).join(', ')}\n${(role['permissions'] as List).join(', ')}'),
                ] else
                  const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
              ]);
            },
          ),
        ),
      ),
      SectionTitle('Account'),
      Card(
        child: Column(children: [
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            onTap: () => FirebaseAuth.instance.signOut(),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.exit_to_app, color: Brand.red),
            title: const Text('Leave this family', style: TextStyle(color: Brand.red)),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Leave this family?'),
                  content: const Text('You will lose access to the pot. You can rejoin with the invite code.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Leave')),
                  ],
                ),
              );
              if (ok == true) {
                try {
                  await Api.instance.leaveFamily(f.id);
                } catch (e) {
                  if (context.mounted) showError(context, e);
                }
              }
            },
          ),
        ]),
      ),
    ]);
  }
}
