import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:passkeys/authenticator.dart';
import 'package:passkeys/types.dart';

import '../../domain/auth/auth_failure.dart';
import '../api/dio_client.dart';

/// One passkey the signed-in user has enrolled.
typedef PasskeySummary = ({String id, String name});

/// Enrols, lists and removes the signed-in user's passkeys.
///
/// Lives outside `IAuthRepository` on purpose: `dioProvider` builds its
/// interceptor from `sessionEnderProvider` → `authRepositoryProvider`, so the
/// auth repository cannot depend on the authenticated Dio without a cycle.
/// This client reads `dioProvider` directly and lets the interceptor attach the
/// bearer token — it never adds one itself.
class PasskeyEnroller {
  PasskeyEnroller(this._dio, {PasskeyAuthenticator? passkeyAuthenticator})
    : _passkeyAuthenticator = passkeyAuthenticator ?? PasskeyAuthenticator();

  final Dio _dio;
  final PasskeyAuthenticator _passkeyAuthenticator;

  static const _startPath = '/api/MobileAuth/passkey/register/start';
  static const _completePath = '/api/MobileAuth/passkey/register/complete';
  static const _listPath = '/api/MobileAuth/passkey';

  /// Enrols a new passkey under [name].
  ///
  /// A dismissed platform sheet is not an error: it returns
  /// `(ok: false, failure: null)` so the caller can stay silent.
  Future<({bool ok, AuthFailure? failure})> enrol({required String name}) async {
    final String passkeyId;
    final RegisterRequestType request;
    try {
      final response = await _dio.post<dynamic>(_startPath, data: const <String, dynamic>{});
      final data = response.data;
      final rawId = data is Map ? data['passkeyId'] : null;
      final rawOptions = data is Map ? data['publicKeyCredentialCreationOptions'] : null;
      // ZITADEL wraps the creation options in a top-level `publicKey`; the
      // package's parser expects the inner object.
      final publicKey = rawOptions is Map ? rawOptions['publicKey'] : null;
      if (rawId is! String || rawId.isEmpty || publicKey is! Map) {
        return (ok: false, failure: const UnknownAuthError('Malformed passkey start response'));
      }
      passkeyId = rawId;
      request = RegisterRequestType.fromJson(Map<String, dynamic>.from(publicKey));
    } on DioException catch (e) {
      return (ok: false, failure: _mapDioError(e));
    } catch (_) {
      // A publicKey shape the package rejects must surface as a typed failure,
      // never escape as a raw FormatException/TypeError.
      return (ok: false, failure: const UnknownAuthError('Malformed passkey start response'));
    }

    final RegisterResponseType credential;
    try {
      credential = await _passkeyAuthenticator.register(request);
    } on PasskeyAuthCancelledException {
      return (ok: false, failure: null);
    } on DomainNotAssociatedException {
      // Wrong RP ID or missing app-site association files.
      return (ok: false, failure: const PasskeyUnavailable());
    } on PasskeyUnsupportedException {
      return (ok: false, failure: const PasskeyUnavailable());
    } on DeviceNotSupportedException {
      return (ok: false, failure: const PasskeyUnavailable());
    } on MissingGoogleSignInException {
      // Android needs a Google account before it can create a passkey.
      return (ok: false, failure: const PasskeyUnavailable());
    } on SyncAccountNotAvailableException {
      return (ok: false, failure: const PasskeyUnavailable());
    } catch (e) {
      return (ok: false, failure: UnknownAuthError(e.toString()));
    }

    try {
      await _dio.post<dynamic>(
        _completePath,
        data: {
          'passkeyId': passkeyId,
          'publicKeyCredential': credential.toJson(),
          'passkeyName': name,
        },
      );
      return (ok: true, failure: null);
    } on DioException catch (e) {
      return (ok: false, failure: _mapDioError(e));
    } catch (e) {
      return (ok: false, failure: UnknownAuthError(e.toString()));
    }
  }

  /// The signed-in user's enrolled passkeys.
  ///
  /// A transport or parsing failure is reported as [failure] rather than
  /// collapsed into an empty list: an empty list is a factual answer ("no
  /// passkeys enrolled"), not an error state.
  Future<({List<PasskeySummary> items, AuthFailure? failure})> list() async {
    try {
      final response = await _dio.get<dynamic>(_listPath);
      final data = response.data;
      if (data is! List) {
        return (
          items: const <PasskeySummary>[],
          failure: const UnknownAuthError('Malformed passkey list response'),
        );
      }
      return (
        items: [
          for (final row in data.whereType<Map>())
            if (row['id'] is String && (row['id'] as String).isNotEmpty)
              (id: row['id'] as String, name: row['name'] is String ? row['name'] as String : ''),
        ],
        failure: null,
      );
    } on DioException catch (e) {
      return (items: const <PasskeySummary>[], failure: _mapListDioError(e));
    } catch (e) {
      return (items: const <PasskeySummary>[], failure: UnknownAuthError(e.toString()));
    }
  }

  /// Removes the passkey [id].
  Future<({bool ok, AuthFailure? failure})> remove(String id) async {
    try {
      await _dio.delete<dynamic>('$_listPath/${Uri.encodeComponent(id)}');
      return (ok: true, failure: null);
    } on DioException catch (e) {
      return (ok: false, failure: _mapDioError(e));
    } catch (e) {
      return (ok: false, failure: UnknownAuthError(e.toString()));
    }
  }

  /// Maps a [list] failure.
  ///
  /// The list path shares no user-facing action with enrolment, so the admin service's generic
  /// `passkey_registration_failed` code (every non-auth 4xx) must not surface as "could not
  /// enable the passkey". Any other 4xx is likewise a list failure, with the list's own copy.
  /// Transport failures keep [NetworkError] so the retry advice stays accurate.
  AuthFailure _mapListDioError(DioException e) {
    final data = e.response?.data;
    final code = data is Map && data['code'] is String ? data['code'] as String : null;
    final status = e.response?.statusCode;
    if (code == 'passkey_registration_failed' ||
        (status != null && status >= 400 && status < 500)) {
      return const UnknownAuthError('Impossibile caricare le passkey.');
    }
    return _mapDioError(e);
  }

  /// Maps the enrolment endpoints' typed error codes onto failures.
  ///
  /// A response with no code at all (network, proxy) falls through to the
  /// transport classification; an unknown code is preserved in
  /// [UnknownAuthError] rather than lost.
  AuthFailure _mapDioError(DioException e) {
    final data = e.response?.data;
    final code = data is Map && data['code'] is String ? data['code'] as String : null;
    if (code == 'passkey_registration_failed') {
      return const PasskeyRegistrationFailed();
    }
    if (code == 'passkey_verification_failed') {
      return const PasskeyVerificationFailed();
    }
    if (code == 'identity_provider_unavailable') {
      return const ServiceUnavailable();
    }
    if (code != null) return UnknownAuthError(code);
    return switch (e.type) {
      DioExceptionType.connectionError ||
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => const NetworkError(),
      _ => UnknownAuthError(e.message ?? e.type.name),
    };
  }
}

/// Provides [PasskeyEnroller]. Override in tests with a fake.
final passkeyEnrollerProvider = Provider<PasskeyEnroller>(
  (ref) => PasskeyEnroller(ref.watch(dioProvider)),
);
