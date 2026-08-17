// dart format width=100
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dio_client.dart';

// ══════════════════════════════════════════════════════════════════════════════
// GDPR — what the company holds about the person holding the phone
//
// `/api/Gdpr/consent`, `/api/Gdpr/export` and `DELETE /api/Gdpr/account` have
// been live and complete on the server, and `lib/` contained zero references to
// any of them. A technician using only the mobile app had no way to see what
// was recorded about them — including, on the cantiere worklogs, a location
// history of their working day.
//
// Two deliberate omissions:
//
// 1. **No deletion.** The endpoint anonymises the user and deactivates them.
//    On a company-issued phone that destroys an identity payroll and invoicing
//    depend on, and the person best placed to understand that consequence is
//    not standing in a plant room. The screen says where to ask instead.
//
// 2. **No consent writing.** `consentType` is a free string and nothing in
//    either codebase enumerates the valid values. Writing an unrecognised type
//    into a legal record is worse than not offering the control, so consent is
//    read-only until the catalogue is pinned down.
//
// These routes carry no response schema in `docs/api/openapi.snapshot.json`
// (the controller returns anonymous objects), so the mobile conformance gate
// cannot guard them. Everything below parses defensively for that reason: an
// absent category reads as unknown, never as zero.
// ══════════════════════════════════════════════════════════════════════════════

/// One consent on record, as the server last stated it.
class ConsentStatus {
  const ConsentStatus({
    required this.consentType,
    required this.granted,
    required this.grantedAt,
    this.consentVersion,
  });

  final String consentType;
  final bool granted;
  final DateTime? grantedAt;
  final String? consentVersion;

  static ConsentStatus? fromJson(Map<String, dynamic> json) {
    final type = json['consentType'];
    if (type is! String || type.isEmpty) return null;
    final at = json['grantedAt'];
    return ConsentStatus(
      consentType: type,
      granted: json['granted'] as bool? ?? false,
      grantedAt: at is String ? DateTime.tryParse(at)?.toLocal() : null,
      consentVersion: json['consentVersion'] as String?,
    );
  }
}

/// The identity fields held about the subject.
class PersonalIdentity {
  const PersonalIdentity({
    this.email,
    this.firstName,
    this.lastName,
    this.phone,
    this.staffCode,
    this.createdAt,
  });

  final String? email;
  final String? firstName;
  final String? lastName;
  final String? phone;
  final String? staffCode;
  final DateTime? createdAt;

  String? get fullName {
    final parts = [firstName, lastName].where((p) => p != null && p.isNotEmpty);
    return parts.isEmpty ? null : parts.join(' ');
  }

  factory PersonalIdentity.fromJson(Map<String, dynamic> json) {
    final created = json['createdAt'];
    return PersonalIdentity(
      email: json['email'] as String?,
      firstName: json['firstName'] as String?,
      lastName: json['lastName'] as String?,
      phone: json['phone'] as String?,
      staffCode: json['staffCode'] as String?,
      createdAt: created is String ? DateTime.tryParse(created)?.toLocal() : null,
    );
  }
}

/// One kind of record held about the subject, and how many of them there are.
class DataCategory {
  const DataCategory({required this.label, required this.count, this.nota});

  final String label;

  /// Null when the server did not send this category at all. Rendering that as `0` would claim the
  /// company holds nothing of this kind, which is a different — and possibly false — statement.
  final int? count;

  /// Said out loud where the category is more sensitive than its name suggests.
  final String? nota;
}

/// Everything `/api/Gdpr/export` says is held, reduced to what a phone can usefully show.
///
/// The full payload runs to every field of every rapportino the subject ever wrote. That is a file,
/// not a screen, and this app has no share sheet to hand it off with — so mobile answers the
/// question the phone is actually good for ("what do you have on me, and how much of it"), and
/// points at the web app for a machine-readable copy.
class PersonalDataSummary {
  const PersonalDataSummary({
    required this.exportDate,
    required this.identity,
    required this.categories,
  });

  final DateTime? exportDate;
  final PersonalIdentity? identity;
  final List<DataCategory> categories;

  /// The categories, in the order they matter to the person reading them: their own work first,
  /// the location trail flagged, infrastructure last.
  static const _spec = <({String key, String label, String? nota})>[
    (key: 'reports', label: 'Rapportini che hai scritto', nota: null),
    (
      key: 'workLogs',
      label: 'Timbrature della giornata',
      nota: 'Le ore da cui si calcola la busta paga.',
    ),
    (key: 'ticketWorkLogs', label: 'Ore registrate sui ticket', nota: null),
    (
      key: 'cantiereWorkLogs',
      label: 'Timbrature di cantiere',
      // The single most sensitive category in the export, and the one nobody would guess from its
      // name. Article 15 exists to make exactly this visible.
      nota: 'Includono le coordinate GPS di arrivo e di uscita dal cantiere.',
    ),
    (key: 'schedules', label: 'Interventi che ti sono stati assegnati', nota: null),
    (key: 'attachments', label: 'File che hai caricato (foto, firme)', nota: null),
    (key: 'notifications', label: 'Notifiche ricevute', nota: null),
    (
      key: 'devices',
      label: 'Dispositivi registrati',
      nota: 'Modello e ultimo accesso. Il token di notifica non è incluso.',
    ),
  ];

  factory PersonalDataSummary.fromJson(Map<String, dynamic> json) {
    final exported = json['exportDate'];
    final user = json['user'];

    return PersonalDataSummary(
      exportDate: exported is String ? DateTime.tryParse(exported)?.toLocal() : null,
      identity: user is Map<String, dynamic> ? PersonalIdentity.fromJson(user) : null,
      categories: [
        for (final spec in _spec)
          DataCategory(
            label: spec.label,
            count: json[spec.key] is List ? (json[spec.key] as List).length : null,
            nota: spec.nota,
          ),
      ],
    );
  }
}

class GdprApiClient {
  GdprApiClient(this._dio);

  final Dio _dio;

  /// The consents on record. An empty list is a real answer — it means none were ever given.
  Future<List<ConsentStatus>> getConsents() async {
    final response = await _dio.get<List<dynamic>>('/api/Gdpr/consent');
    return [
      for (final row in response.data ?? const [])
        if (row is Map<String, dynamic>) ?ConsentStatus.fromJson(row),
    ];
  }

  Future<PersonalDataSummary> getSummary() async {
    final response = await _dio.get<Map<String, dynamic>>('/api/Gdpr/export');
    final data = response.data;
    if (data == null) throw StateError('Risposta vuota da /api/Gdpr/export');
    return PersonalDataSummary.fromJson(data);
  }
}

final gdprApiClientProvider = Provider<GdprApiClient>((ref) => GdprApiClient(ref.watch(dioProvider)));

/// Online-only, deliberately. This is the server's statement about what it holds; a cached copy
/// would let the app assert something the company may have changed since, on the one screen where
/// being out of date is itself the problem.
final personalDataSummaryProvider = FutureProvider.autoDispose<PersonalDataSummary>((ref) {
  return ref.watch(gdprApiClientProvider).getSummary();
});

final consentStatusProvider = FutureProvider.autoDispose<List<ConsentStatus>>((ref) {
  return ref.watch(gdprApiClientProvider).getConsents();
});
