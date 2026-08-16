import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/gdpr/gdpr_api_client.dart';

/// Parsing rules for the subject-access surface.
///
/// These routes carry no response schema in `docs/api/openapi.snapshot.json` — the controller
/// returns anonymous objects — so the mobile conformance gate cannot guard them and these tests are
/// the only thing standing between a contract change and a screen that lies about what is held on
/// someone. The load-bearing rule is the last group: **absent is not zero.**
void main() {
  Map<String, dynamic> export({Map<String, dynamic>? overrides}) => {
    'exportDate': '2026-08-16T09:30:00Z',
    'user': {
      'email': 'mario@tasktap.io',
      'firstName': 'Mario',
      'lastName': 'Rossi',
      'phone': '+39 333 1234567',
      'staffCode': 'T-014',
      'createdAt': '2025-03-04T08:00:00Z',
    },
    'reports': [{}, {}, {}],
    'workLogs': [{}],
    'ticketWorkLogs': <dynamic>[],
    'cantiereWorkLogs': [{}, {}],
    'schedules': <dynamic>[],
    'attachments': [{}],
    'notifications': <dynamic>[],
    'devices': [{}],
    ...?overrides,
  };

  DataCategory categoryNamed(PersonalDataSummary summary, String label) =>
      summary.categories.firstWhere((c) => c.label == label);

  group('identity', () {
    test('the person is named the way they would name themselves', () {
      final summary = PersonalDataSummary.fromJson(export());
      expect(summary.identity!.fullName, 'Mario Rossi');
      expect(summary.identity!.staffCode, 'T-014');
    });

    test('a half-filled name does not produce a stray space', () {
      final summary = PersonalDataSummary.fromJson(
        export(overrides: {
          'user': {'firstName': 'Mario', 'lastName': ''},
        }),
      );
      expect(summary.identity!.fullName, 'Mario');
    });

    test('no user block at all is survivable', () {
      final summary = PersonalDataSummary.fromJson(export(overrides: {'user': null}));
      expect(summary.identity, isNull);
      expect(summary.categories, isNotEmpty);
    });

    test('timestamps are localised, not left in UTC for a technician to convert', () {
      final summary = PersonalDataSummary.fromJson(export());
      expect(summary.exportDate!.isUtc, isFalse);
    });
  });

  group('categories', () {
    test('counts come from the length of what the server actually sent', () {
      final summary = PersonalDataSummary.fromJson(export());
      expect(categoryNamed(summary, 'Rapportini che hai scritto').count, 3);
      expect(categoryNamed(summary, 'Timbrature di cantiere').count, 2);
    });

    test('the location trail is named out loud', () {
      // The single most revealing category in the export and the one nobody would guess from its
      // label. If this note disappears, the screen stops disclosing the thing most worth
      // disclosing.
      final nota = categoryNamed(
        PersonalDataSummary.fromJson(export()),
        'Timbrature di cantiere',
      ).nota;
      expect(nota, contains('GPS'));
    });

    test('every category is rendered even when it is empty', () {
      final summary = PersonalDataSummary.fromJson(export());
      expect(categoryNamed(summary, 'Notifiche ricevute').count, 0);
      expect(summary.categories.length, 8);
    });
  });

  group('absent is not zero', () {
    test('a category the server omitted has no count, rather than a count of zero', () {
      // Rendering an omitted category as `0` claims the company holds nothing of that kind. We
      // were not told that — we were told nothing — and on a subject access request the difference
      // between "none" and "not disclosed" is the whole point.
      final json = export()..remove('cantiereWorkLogs');
      final summary = PersonalDataSummary.fromJson(json);
      expect(categoryNamed(summary, 'Timbrature di cantiere').count, isNull);
    });

    test('a category sent as something other than a list is treated as not disclosed', () {
      final summary = PersonalDataSummary.fromJson(export(overrides: {'reports': 'many'}));
      expect(categoryNamed(summary, 'Rapportini che hai scritto').count, isNull);
    });

    test('an empty list still means zero, and must not be confused with absence', () {
      final summary = PersonalDataSummary.fromJson(export(overrides: {'reports': <dynamic>[]}));
      expect(categoryNamed(summary, 'Rapportini che hai scritto').count, 0);
    });
  });

  group('consents', () {
    test('a row without a consent type is dropped rather than shown as blank', () {
      expect(ConsentStatus.fromJson({'granted': true}), isNull);
      expect(ConsentStatus.fromJson({'consentType': '', 'granted': true}), isNull);
    });

    test('a granted consent keeps its date and version', () {
      final consent = ConsentStatus.fromJson({
        'consentType': 'privacy',
        'granted': true,
        'grantedAt': '2026-01-15T10:00:00Z',
        'consentVersion': 'v2',
      })!;
      expect(consent.granted, isTrue);
      expect(consent.consentVersion, 'v2');
      expect(consent.grantedAt!.isUtc, isFalse);
    });

    test('an unparseable date does not take the whole consent with it', () {
      final consent = ConsentStatus.fromJson({
        'consentType': 'marketing',
        'granted': false,
        'grantedAt': 'never',
      })!;
      expect(consent.consentType, 'marketing');
      expect(consent.grantedAt, isNull);
    });
  });
}
