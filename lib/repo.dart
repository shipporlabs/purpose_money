import 'package:cloud_firestore/cloud_firestore.dart';

import 'models.dart';

/// Real-time reads straight from Firestore. Writes go through [Api].
class Repo {
  Repo._();
  static final instance = Repo._();
  final _db = FirebaseFirestore.instance;

  Stream<Profile> profile(String uid) =>
      _db.doc('users/$uid').snapshots().map((s) => Profile.from(uid, s.data()));

  Stream<Family?> family(String id) =>
      _db.doc('families/$id').snapshots().map((s) => s.exists ? Family(s.id, s.data()!) : null);

  Stream<List<Merchant>> merchants(String familyId) => _db
      .collection('families/$familyId/merchants')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((q) => q.docs.map((d) => Merchant(d.id, d.data())).toList());

  Stream<List<Payment>> payments(String familyId, {int limit = 50}) => _db
      .collection('families/$familyId/payments')
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((q) => q.docs.map((d) => Payment(d.id, d.data())).toList());

  Stream<Payment?> payment(String familyId, String id) =>
      _db.doc('families/$familyId/payments/$id').snapshots().map((s) => s.exists ? Payment(s.id, s.data()!) : null);

  Stream<List<Contribution>> contributions(String familyId, {int limit = 50}) => _db
      .collection('families/$familyId/contributions')
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((q) => q.docs.map((d) => Contribution(d.id, d.data())).toList());

  Stream<Contribution?> contribution(String familyId, String id) => _db
      .doc('families/$familyId/contributions/$id')
      .snapshots()
      .map((s) => s.exists ? Contribution(s.id, s.data()!) : null);

  Stream<List<Change>> changes(String familyId) => _db
      .collection('families/$familyId/changes')
      .orderBy('createdAt', descending: true)
      .limit(30)
      .snapshots()
      .map((q) => q.docs.map((d) => Change(d.id, d.data())).toList());

  Future<void> ensureProfile(String uid, String displayName, String? email) async {
    final ref = _db.doc('users/$uid');
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({'displayName': displayName, 'email': email, 'createdAt': FieldValue.serverTimestamp()});
    }
  }

  Future<void> updateDisplayName(String uid, String name) => _db.doc('users/$uid').update({'displayName': name});
}
