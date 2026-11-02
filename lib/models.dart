import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
double _dbl(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
String _str(Object? v) => v?.toString() ?? '';
DateTime? _date(Object? v) => v is Timestamp ? v.toDate() : v is DateTime ? v : null;
List<String> _list(Object? v) => v is List ? v.map((e) => e.toString()).toList() : <String>[];
Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

class Profile {
  Profile({required this.uid, required this.displayName, this.email, this.familyId, this.role});
  final String uid;
  final String displayName;
  final String? email;
  final String? familyId;
  final String? role; // 'sibling' | 'parent'

  bool get isSibling => role == 'sibling';
  bool get isParent => role == 'parent';

  factory Profile.from(String uid, Map<String, dynamic>? d) => Profile(
        uid: uid,
        displayName: _str(d?['displayName']).isEmpty ? 'You' : _str(d?['displayName']),
        email: d?['email'] as String?,
        familyId: (d?['familyId'] as String?)?.isEmpty == true ? null : d?['familyId'] as String?,
        role: d?['role'] as String?,
      );
}

class Purpose {
  Purpose({required this.key, required this.label, required this.budgetNgn, required this.spentNgn});
  final String key;
  final String label;
  final int budgetNgn;
  final int spentNgn;
  int get remainingNgn => math.max(0, budgetNgn - spentNgn);
  double get progress => budgetNgn <= 0 ? 0 : (spentNgn / budgetNgn).clamp(0.0, 1.0);
}

class Rules {
  Rules(this.raw);
  final Map<String, dynamic> raw;
  int get autoApproveLimitNgn => _int(raw['autoApproveLimitNgn']);
  int get dailyCapPerMerchantNgn => _int(raw['dailyCapPerMerchantNgn']);
  int get newMerchantCooldownHours => _int(raw['newMerchantCooldownHours']);
  int get maxPaymentsPerDay => _int(raw['maxPaymentsPerDay']);
  int get siblingApprovalsRequired => _int(raw['siblingApprovalsRequired']);
}

class Family {
  Family(this.id, this.d);
  final String id;
  final Map<String, dynamic> d;

  String get name => _str(d['name']);
  String get inviteCode => _str(d['inviteCode']);
  int get balanceNgn => _int(d['balanceNgn']);
  List<String> get siblingUids => _list(d['siblingUids']);
  List<String> get parentUids => _list(d['parentUids']);
  Map<String, String> get memberNames => _map(d['memberNames']).map((k, v) => MapEntry(k, _str(v)));
  Map<String, int> get contributedNgn => _map(d['contributedNgn']).map((k, v) => MapEntry(k, _int(v)));
  Rules get rules => Rules(_map(d['rules']));
  String get network => _str(d['network']).isEmpty ? 'testnet' : _str(d['network']);
  Map<String, dynamic> get dao => _map(d['dao']);
  String get daoId => _str(dao['id']);
  String get daoStatus => _str(dao['status']);
  String? get daoError => dao['error'] as String?;
  String nameOf(String uid) => memberNames[uid] ?? 'Family member';
  int get approvalsNeeded {
    final n = rules.siblingApprovalsRequired;
    final s = siblingUids.length;
    return (n < s ? n : s).clamp(1, 99);
  }

  List<Purpose> get purposes {
    final m = _map(d['purposes']);
    final list = m.entries.map((e) {
      final p = _map(e.value);
      return Purpose(key: e.key, label: _str(p['label']), budgetNgn: _int(p['budgetNgn']), spentNgn: _int(p['spentNgn']));
    }).toList();
    const order = ['food', 'rent', 'school'];
    list.sort((a, b) {
      final ia = order.indexOf(a.key), ib = order.indexOf(b.key);
      return (ia < 0 ? 99 : ia).compareTo(ib < 0 ? 99 : ib);
    });
    return list;
  }

  Purpose? purpose(String key) => purposes.where((p) => p.key == key).firstOrNull;
  int get totalBudget => purposes.fold(0, (s, p) => s + p.budgetNgn);
  int get totalSpent => purposes.fold(0, (s, p) => s + p.spentNgn);
}

class Merchant {
  Merchant(this.id, this.d);
  final String id;
  final Map<String, dynamic> d;
  String get displayName => _str(d['displayName']);
  String get accountName => _str(d['accountName']);
  String get accountNumber => _str(d['accountNumber']);
  String get bankName => _str(d['bankName']);
  String get category => _str(d['category']);
  String get status => _str(d['status']);
  double get nameMatch => _dbl(d['nameMatch']);
  List<String> get approvals => _list(d['approvals']);
  List<String> get rejections => _list(d['rejections']);
  int get approvalsNeeded => _int(d['approvalsNeeded']);
  String get addedByName => _str(d['addedByName']);
  DateTime? get createdAt => _date(d['createdAt']);
  bool get approved => status == 'approved';
  String get maskedAccount => accountNumber.length >= 4 ? '•••• ${accountNumber.substring(accountNumber.length - 4)}' : accountNumber;
}

class Check {
  Check(this.d);
  final Map<String, dynamic> d;
  String get id => _str(d['id']);
  String get label => _str(d['label']);
  bool get passed => d['passed'] == true;
  String get severity => _str(d['severity']);
  String get detail => _str(d['detail']);
}

class Payment {
  Payment(this.id, this.d);
  final String id;
  final Map<String, dynamic> d;
  String get merchantId => _str(d['merchantId']);
  String get merchantName => _str(d['merchantName']);
  String get accountName => _str(d['accountName']);
  String get category => _str(d['category']);
  String get purposeLabel => _str(d['purposeLabel']);
  int get amountNgn => _int(d['amountNgn']);
  String get note => _str(d['note']);
  String get status => _str(d['status']);
  String get requestedBy => _str(d['requestedBy']);
  String get requestedByName => _str(d['requestedByName']);
  String? get error => d['error'] as String?;
  List<String> get approvals => _list(d['approvals']);
  List<String> get rejections => _list(d['rejections']);
  int get approvalsNeeded => _int(d['approvalsNeeded']);
  DateTime? get createdAt => _date(d['createdAt']);
  DateTime? get paidAt => _date(d['paidAt']);
  Map<String, dynamic> get decision => _map(d['decision']);
  String get outcome => _str(decision['outcome']);
  String get reason => _str(decision['reason']);
  String? get aiNote => decision['aiNote'] as String?;
  List<Check> get checks => (decision['checks'] as List? ?? []).map((e) => Check(_map(e))).toList();
  Map<String, dynamic> get onchain => _map(d['onchain']);
  Map<String, dynamic> get paystack => _map(d['paystack']);
  bool get isFinal => const ['paid', 'blocked', 'rejected', 'failed'].contains(status);
}

class Contribution {
  Contribution(this.id, this.d);
  final String id;
  final Map<String, dynamic> d;
  String get uid => _str(d['uid']);
  String get name => _str(d['name']);
  String get method => _str(d['method']);
  String get status => _str(d['status']);
  int get amountUsd => _int(d['amountUsd']);
  int get amountNgn => _int(d['amountNgn']);
  String get originSymbol => _str(d['originSymbol']);
  String get originChain => _str(d['originChain']);
  String get amountIn => _str(d['amountIn']);
  String get depositAddress => _str(d['depositAddress']);
  String? get depositMemo => d['depositMemo'] as String?;
  String? get mirrorUrl => d['mirrorUrl'] as String?;
  String? get error => d['error'] as String?;
  DateTime? get createdAt => _date(d['createdAt']);
}

class Change {
  Change(this.id, this.d);
  final String id;
  final Map<String, dynamic> d;
  String get type => _str(d['type']);
  Map<String, dynamic> get payload => _map(d['payload']);
  String get status => _str(d['status']);
  String get proposedBy => _str(d['proposedBy']);
  String get proposedByName => _str(d['proposedByName']);
  List<String> get approvals => _list(d['approvals']);
  List<String> get rejections => _list(d['rejections']);
  int get approvalsNeeded => _int(d['approvalsNeeded']);
  DateTime? get createdAt => _date(d['createdAt']);

  String get summary {
    switch (type) {
      case 'budgets':
        final p = _map(payload['purposes']);
        return 'New budgets: ${p.entries.map((e) => '${_map(e.value)['label']} ₦${_int(_map(e.value)['budgetNgn'])}').join(', ')}';
      case 'rules':
        return 'New guardian rules: ${_map(payload['rules']).entries.map((e) => '${e.key} → ${e.value}').join(', ')}';
      case 'new_month':
        return 'Start a new month (reset what each purpose has spent)';
      default:
        return type;
    }
  }
}
