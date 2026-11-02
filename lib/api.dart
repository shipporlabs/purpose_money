import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'config.dart';

class ApiException implements Exception {
  ApiException(this.message, [this.status]);
  final String message;
  final int? status;
  @override
  String toString() => message;
}

/// Talks to the Cloudflare Worker. Every call carries the Firebase ID token.
class Api {
  Api._();
  static final instance = Api._();

  Future<Map<String, dynamic>> _send(String method, String path, [Map<String, dynamic>? body]) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw ApiException('Please sign in again.', 401);
    final token = await user.getIdToken();
    final uri = Uri.parse('$apiUrl$path');
    final headers = {'authorization': 'Bearer $token', 'content-type': 'application/json'};
    http.Response res;
    try {
      res = method == 'GET'
          ? await http.get(uri, headers: headers).timeout(const Duration(seconds: 45))
          : await http.post(uri, headers: headers, body: jsonEncode(body ?? {})).timeout(const Duration(seconds: 60));
    } catch (_) {
      throw ApiException('Could not reach the Purpose Money server. Check your connection and API_URL.');
    }
    Map<String, dynamic> json;
    try {
      json = res.body.isEmpty ? {} : (jsonDecode(res.body) as Map<String, dynamic>);
    } catch (_) {
      throw ApiException('Unexpected reply from the server (${res.statusCode}).', res.statusCode);
    }
    if (res.statusCode >= 400) throw ApiException(json['error']?.toString() ?? 'Something went wrong (${res.statusCode}).', res.statusCode);
    return json;
  }

  Future<Map<String, dynamic>> get(String path) => _send('GET', path);
  Future<Map<String, dynamic>> post(String path, [Map<String, dynamic>? body]) => _send('POST', path, body);

  // Families
  Future<Map<String, dynamic>> createFamily(String name) => post('/api/families', {'name': name});
  Future<Map<String, dynamic>> joinFamily(String code, String role) => post('/api/families/join', {'inviteCode': code, 'role': role});
  Future<void> leaveFamily(String familyId) => post('/api/families/leave', {'familyId': familyId});
  Future<void> retryDao(String familyId) => post('/api/families/retry-dao', {'familyId': familyId});
  Future<Map<String, dynamic>> chainInfo(String familyId) => post('/api/families/chain', {'familyId': familyId});

  // Merchants
  Future<List<Map<String, dynamic>>> banks() async =>
      ((await get('/api/banks'))['banks'] as List).cast<Map<String, dynamic>>();
  Future<String> resolveAccount(String bankCode, String accountNumber) async =>
      (await post('/api/merchants/resolve', {'bankCode': bankCode, 'accountNumber': accountNumber}))['accountName'] as String;
  Future<Map<String, dynamic>> addMerchant(Map<String, dynamic> body) => post('/api/merchants', body);
  Future<void> voteMerchant(String familyId, String merchantId, bool approve) =>
      post('/api/merchants/vote', {'familyId': familyId, 'merchantId': merchantId, 'approve': approve});

  // Payments
  Future<Map<String, dynamic>> requestPayment(String familyId, String merchantId, int amountNgn, String note) =>
      post('/api/payments', {'familyId': familyId, 'merchantId': merchantId, 'amountNgn': amountNgn, 'note': note});
  Future<void> votePayment(String familyId, String paymentId, bool approve) =>
      post('/api/payments/vote', {'familyId': familyId, 'paymentId': paymentId, 'approve': approve});
  Future<void> retryPayout(String familyId, String paymentId) =>
      post('/api/payments/retry-payout', {'familyId': familyId, 'paymentId': paymentId});

  // Changes
  Future<Map<String, dynamic>> proposeChange(String familyId, String type, Map<String, dynamic> payload) =>
      post('/api/changes', {'familyId': familyId, 'type': type, 'payload': payload});
  Future<void> voteChange(String familyId, String changeId, bool approve) =>
      post('/api/changes/vote', {'familyId': familyId, 'changeId': changeId, 'approve': approve});

  // Funding
  Future<Map<String, dynamic>> fundingTokens() => get('/api/fund/tokens');
  Future<Map<String, dynamic>> fundQuote(String familyId, String assetId, int amountUsd, String refundTo) =>
      post('/api/fund/quote', {'familyId': familyId, 'assetId': assetId, 'amountUsd': amountUsd, 'refundTo': refundTo});
  Future<Map<String, dynamic>> fundStatus(String familyId, String contributionId) =>
      post('/api/fund/status', {'familyId': familyId, 'contributionId': contributionId});
  Future<Map<String, dynamic>> fundTestnet(String familyId, int amountUsd) =>
      post('/api/fund/testnet', {'familyId': familyId, 'amountUsd': amountUsd});
}
