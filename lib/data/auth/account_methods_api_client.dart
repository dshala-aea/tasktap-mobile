// ══════════════════════════════════════════════════════════════════════════════
// AccountMethodsApiClient
//
// Asks the backend which sign-in methods an account actually has, before the
// login screen offers any of them:
//   POST /api/MobileAuth/methods  {loginName} -> {hasPasskey, hasPassword}
//
// The call is anonymous: it runs before a session exists, so it goes through a
// Dio that carries no bearer token. Failures are deliberately not mapped to a
// typed exception — the caller falls back to the old method offer so a broken
// check never blocks sign-in.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dio_client.dart';

class AccountMethods {
  const AccountMethods({required this.hasPasskey, required this.hasPassword});

  final bool hasPasskey;
  final bool hasPassword;

  /// Used when the check itself fails: offer both, exactly as login did before
  /// the endpoint existed. The device gate still hides the passkey button on
  /// hardware that cannot use it.
  static const fallback = AccountMethods(hasPasskey: true, hasPassword: true);

  factory AccountMethods.fromJson(Map<String, dynamic> json) {
    return AccountMethods(
      hasPasskey: json['hasPasskey'] == true,
      hasPassword: json['hasPassword'] == true,
    );
  }
}

class AccountMethodsApiClient {
  AccountMethodsApiClient(this._dio);

  final Dio _dio;

  Future<AccountMethods> fetch(String loginName) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/MobileAuth/methods',
      data: {'loginName': loginName},
    );
    final data = response.data;
    if (data == null) {
      throw const FormatException('Empty account methods response');
    }
    return AccountMethods.fromJson(data);
  }
}

final accountMethodsApiClientProvider = Provider<AccountMethodsApiClient>((
  ref,
) {
  return AccountMethodsApiClient(ref.watch(dioProvider));
});
