import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../format.dart';
import '../models.dart';
import '../theme.dart';

void showError(BuildContext context, Object e) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Brand.red));
}

void showInfo(BuildContext context, String msg) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

Future<void> openUrl(String? url) async {
  if (url == null || url.isEmpty) return;
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

/// Runs an async action with a spinner on the button and an error snackbar on failure.
class BusyButton extends StatefulWidget {
  const BusyButton({super.key, required this.label, required this.onPressed, this.icon, this.outlined = false, this.danger = false});
  final String label;
  final Future<void> Function()? onPressed;
  final IconData? icon;
  final bool outlined;
  final bool danger;

  @override
  State<BusyButton> createState() => _BusyButtonState();
}

class _BusyButtonState extends State<BusyButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (widget.onPressed == null || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.onPressed!();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = _busy
        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
        : Row(mainAxisSize: MainAxisSize.min, children: [
            if (widget.icon != null) ...[Icon(widget.icon, size: 20), const SizedBox(width: 8)],
            Flexible(child: Text(widget.label, overflow: TextOverflow.ellipsis)),
          ]);
    final onPressed = widget.onPressed == null || _busy ? null : _run;
    if (widget.outlined) {
      return OutlinedButton(
        onPressed: onPressed,
        style: widget.danger ? OutlinedButton.styleFrom(foregroundColor: Brand.red, side: const BorderSide(color: Brand.redSoft, width: 1.5)) : null,
        child: child,
      );
    }
    return FilledButton(onPressed: onPressed, child: child);
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
        child: Row(children: [
          Expanded(child: Text(text, style: display(19))),
          if (trailing != null) trailing!,
        ]),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.body});
  final IconData icon;
  final String title;
  final String? body;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            Icon(icon, size: 36, color: Brand.green),
            const SizedBox(height: 10),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            if (body != null) ...[
              const SizedBox(height: 6),
              Text(body!, textAlign: TextAlign.center, style: const TextStyle(color: Brand.muted, height: 1.45)),
            ],
          ]),
        ),
      );
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final String status;

  static (String, Color, Color) styleFor(String s) {
    switch (s) {
      case 'paid':
      case 'approved':
      case 'applied':
      case 'credited':
      case 'active':
        return (s == 'paid' ? 'Paid' : s == 'credited' ? 'Credited' : s == 'active' ? 'Live' : s == 'applied' ? 'Applied' : 'Approved', Brand.mint, Brand.green);
      case 'paying':
      case 'crediting':
      case 'checking':
      case 'creating':
      case 'processing':
      case 'known_deposit_tx':
        return ('In progress', Brand.amberSoft, const Color(0xFF7A4F00));
      case 'escalated':
      case 'pending':
      case 'awaiting_deposit':
      case 'pending_deposit':
        return (s == 'escalated' ? 'Needs family OK' : s == 'pending' ? 'Pending' : 'Awaiting deposit', const Color(0xFFE3E6F5), Brand.blue);
      case 'blocked':
      case 'rejected':
      case 'failed':
      case 'payout_failed':
      case 'credit_failed':
      case 'refunded':
      case 'incomplete_deposit':
        return (
          {'blocked': 'Blocked', 'rejected': 'Rejected', 'payout_failed': 'Payout failed', 'credit_failed': 'Credit failed', 'refunded': 'Refunded', 'incomplete_deposit': 'Incomplete'}[s] ?? 'Failed',
          Brand.redSoft,
          Brand.red
        );
      default:
        return (s, Brand.line, Brand.muted);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = styleFor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 12)),
    );
  }
}

class PurposeBar extends StatelessWidget {
  const PurposeBar(this.purpose, {super.key});
  final Purpose purpose;

  static Color colorFor(String key) {
    switch (key) {
      case 'food':
        return Brand.accent;
      case 'school':
        return Brand.green;
      case 'rent':
        return Brand.blue;
      default:
        return const Color(0xFF8A5A00);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Brand.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(purpose.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
            Text('${naira(purpose.remainingNgn)} left', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: purpose.progress, minHeight: 8, backgroundColor: const Color(0xFFECEAE2), color: colorFor(purpose.key),
            ),
          ),
          const SizedBox(height: 8),
          Text('${naira(purpose.spentNgn)} spent of ${naira(purpose.budgetNgn)}', style: const TextStyle(color: Brand.muted, fontSize: 13)),
        ]),
      );
}

class PaymentTile extends StatelessWidget {
  const PaymentTile(this.p, {super.key, this.onTap});
  final Payment p;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: PurposeBar.colorFor(p.category).withValues(alpha: 0.18),
          child: Icon(Icons.storefront_outlined, color: PurposeBar.colorFor(p.category) == Brand.accent ? const Color(0xFF7A4F00) : PurposeBar.colorFor(p.category)),
        ),
        title: Text(p.merchantName, style: const TextStyle(fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis),
        subtitle: Text('${p.purposeLabel} · ${p.requestedByName} · ${timeAgo(p.createdAt)}', overflow: TextOverflow.ellipsis),
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(naira(p.amountNgn), style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          StatusChip(p.status),
        ]),
      );
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.onTap});
  final String label;
  final String value;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 130, child: Text(label, style: const TextStyle(color: Brand.muted, fontWeight: FontWeight.w600))),
            Expanded(
              child: Text(value,
                  style: TextStyle(fontWeight: FontWeight.w700, color: onTap != null ? Brand.green : Brand.ink, decoration: onTap != null ? TextDecoration.underline : null)),
            ),
          ]),
        ),
      );
}

/// Centers content and caps its width so the app looks right on web and tablets.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 32)});
  final List<Widget> children;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(padding: padding, children: children),
        ),
      );
}
