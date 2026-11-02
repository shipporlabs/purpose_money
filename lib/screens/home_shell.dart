import 'package:flutter/material.dart';

import '../models.dart';
import '../repo.dart';
import '../widgets/brand_mark.dart';
import 'activity_screen.dart';
import 'approvals_screen.dart';
import 'family_screen.dart';
import 'home_tab.dart';
import 'shops_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.profile});
  final Profile profile;
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    return StreamBuilder<Family?>(
      stream: Repo.instance.family(profile.familyId!),
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Could not load your family: ${snap.error}'))));
        }
        if (!snap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final family = snap.data;
        if (family == null) return const Scaffold(body: Center(child: Text('This family no longer exists.')));

        final sibling = profile.isSibling;
        final pages = <Widget>[
          HomeTab(profile: profile, family: family),
          if (sibling) ApprovalsScreen(profile: profile, family: family) else ShopsScreen(profile: profile, family: family),
          ActivityScreen(profile: profile, family: family),
          FamilyScreen(profile: profile, family: family),
        ];
        final destinations = <NavigationDestination>[
          const NavigationDestination(icon: Icon(Icons.savings_outlined), selectedIcon: Icon(Icons.savings), label: 'Pot'),
          if (sibling)
            NavigationDestination(
              icon: _ApprovalsBadge(familyId: family.id, uid: profile.uid, child: const Icon(Icons.how_to_vote_outlined)),
              selectedIcon: const Icon(Icons.how_to_vote),
              label: 'Approvals',
            )
          else
            const NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'Shops'),
          const NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Activity'),
          const NavigationDestination(icon: Icon(Icons.diversity_3_outlined), selectedIcon: Icon(Icons.diversity_3), label: 'Family'),
        ];
        return Scaffold(
          appBar: AppBar(title: const BrandMark(size: 26)),
          body: IndexedStack(index: _tab, children: pages),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: destinations,
          ),
        );
      },
    );
  }
}

/// Shows how many items are waiting on this sibling's vote.
class _ApprovalsBadge extends StatelessWidget {
  const _ApprovalsBadge({required this.familyId, required this.uid, required this.child});
  final String familyId;
  final String uid;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Merchant>>(
      stream: Repo.instance.merchants(familyId),
      builder: (context, m) => StreamBuilder<List<Payment>>(
        stream: Repo.instance.payments(familyId, limit: 30),
        builder: (context, p) => StreamBuilder<List<Change>>(
          stream: Repo.instance.changes(familyId),
          builder: (context, c) {
            final n = (m.data ?? []).where((x) => x.status == 'pending' && !x.approvals.contains(uid) && !x.rejections.contains(uid)).length +
                (p.data ?? []).where((x) => x.status == 'escalated' && !x.approvals.contains(uid) && !x.rejections.contains(uid)).length +
                (c.data ?? []).where((x) => x.status == 'pending' && !x.approvals.contains(uid) && !x.rejections.contains(uid)).length;
            return n == 0 ? child : Badge(label: Text('$n'), child: child);
          },
        ),
      ),
    );
  }
}
