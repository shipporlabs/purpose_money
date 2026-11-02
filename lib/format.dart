import 'package:intl/intl.dart';

final _naira = NumberFormat.currency(locale: 'en_US', symbol: '₦', decimalDigits: 0);
String naira(num v) => _naira.format(v);

String timeAgo(DateTime? t) {
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return DateFormat('d MMM').format(t);
}

String shortAccount(String id) => id.length <= 28 ? id : '${id.substring(0, 14)}…${id.substring(id.length - 12)}';

String initial(String name) => name.trim().isEmpty ? '?' : name.trim().substring(0, 1).toUpperCase();
