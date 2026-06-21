// Tests for DraftValidation — M4
//
// Verifies that local validation mirrors server ReportStateMachine rules:
//   - Missing title → flagged
//   - Missing customer (no id AND no freeText) → flagged
//   - No staff → flagged
//   - No materiali AND materialiNotRequired=false → flagged
//   - No materiali but materialiNotRequired=true → OK
//   - Missing customer firma → flagged
//   - Missing technician firma → flagged
//   - All rules pass → isValid=true, isReadyToSubmit=true
//   - Italian messages for each issue

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/domain/reports/draft_validation.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

Future<DraftReport> _insertDraft(
  AppDatabase db, {
  String id = 'r-1',
  String title = 'Test rapportino',
  String? customerId = 'cust-1',
  String? customerSignatureAllegatoId = 'sig-cust-1',
  String? technicianSignatureAllegatoId = 'sig-tech-1',
  bool materialiNotRequired = false,
}) async {
  await db.into(db.draftReports).insert(
        DraftReportsCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 6, 21),
          title: title,
          insertedUserId: 'user-1',
          locationId: 'loc-1',
          customerId: Value(customerId),
          customerSignatureAllegatoId: Value(customerSignatureAllegatoId),
          technicianSignatureAllegatoId: Value(technicianSignatureAllegatoId),
          materialiNotRequired: Value(materialiNotRequired),
          isLocalOnly: const Value(true),
        ),
      );
  return (await db.select(db.draftReports)
        ..where((r) => r.id.equals(id)))
      .getSingle();
}

// ══════════════════════════════════════════════════════════════════════════════
// Tests
// ══════════════════════════════════════════════════════════════════════════════

void main() {
  late AppDatabase db;

  setUp(() => db = _makeDb());
  tearDown(() async => db.close());

  // ── Full-valid draft ───────────────────────────────────────────────────────

  group('validateDraft — fully valid draft', () {
    test('isValid when all requirements are met', () async {
      final draft = await _insertDraft(db, materialiNotRequired: false);

      final result = validateDraft(
        draft: draft,
        staffCount: 1,
        materialiCount: 1,
      );

      expect(result.isValid, isTrue);
      expect(result.issues, isEmpty);
      expect(result.isReadyToSubmit, isTrue);
    });

    test('isValid when materialiNotRequired=true and no materiali', () async {
      final draft = await _insertDraft(db, materialiNotRequired: true);

      final result = validateDraft(
        draft: draft,
        staffCount: 1,
        materialiCount: 0,
      );

      expect(result.isValid, isTrue);
    });
  });

  // ── Individual missing requirements ───────────────────────────────────────

  group('validateDraft — individual requirements', () {
    test('flags missingTitle when title is empty', () async {
      final draft = await _insertDraft(db, title: '   ');

      final result = validateDraft(
        draft: draft,
        staffCount: 1,
        materialiCount: 1,
      );

      expect(result.issues, contains(DraftValidationIssue.missingTitle));
    });

    test('flags missingTitle when title is blank', () async {
      final draft = await _insertDraft(db, title: '');

      final result = validateDraft(
        draft: draft,
        staffCount: 1,
        materialiCount: 1,
      );

      expect(result.issues, contains(DraftValidationIssue.missingTitle));
    });

    test('flags missingCustomer when no customerId and no freeText', () async {
      final draft = await _insertDraft(db, customerId: null);

      final result = validateDraft(
        draft: draft,
        staffCount: 1,
        materialiCount: 1,
        customerFreeText: null,
      );

      expect(result.issues, contains(DraftValidationIssue.missingCustomer));
    });

    test('does NOT flag missingCustomer when customerFreeText is provided',
        () async {
      final draft = await _insertDraft(db, customerId: null);

      final result = validateDraft(
        draft: draft,
        staffCount: 1,
        materialiCount: 1,
        customerFreeText: 'ACME srl',
      );

      expect(
        result.issues,
        isNot(contains(DraftValidationIssue.missingCustomer)),
      );
    });

    test('does NOT flag missingCustomer when customerId is set', () async {
      final draft = await _insertDraft(db, customerId: 'cust-1');

      final result = validateDraft(
        draft: draft,
        staffCount: 1,
        materialiCount: 1,
      );

      expect(
        result.issues,
        isNot(contains(DraftValidationIssue.missingCustomer)),
      );
    });

    test('flags noStaff when staffCount == 0', () async {
      final draft = await _insertDraft(db);

      final result = validateDraft(
        draft: draft,
        staffCount: 0,
        materialiCount: 1,
      );

      expect(result.issues, contains(DraftValidationIssue.noStaff));
    });

    test('does NOT flag noStaff when staffCount > 0', () async {
      final draft = await _insertDraft(db);

      final result = validateDraft(
        draft: draft,
        staffCount: 2,
        materialiCount: 1,
      );

      expect(result.issues, isNot(contains(DraftValidationIssue.noStaff)));
    });

    test(
        'flags noMateriali when materialiCount == 0 and materialiNotRequired = false',
        () async {
      final draft = await _insertDraft(db, materialiNotRequired: false);

      final result = validateDraft(
        draft: draft,
        staffCount: 1,
        materialiCount: 0,
      );

      expect(result.issues, contains(DraftValidationIssue.noMateriali));
    });

    test(
        'does NOT flag noMateriali when materialiNotRequired = true and count = 0',
        () async {
      final draft = await _insertDraft(db, materialiNotRequired: true);

      final result = validateDraft(
        draft: draft,
        staffCount: 1,
        materialiCount: 0,
      );

      expect(result.issues, isNot(contains(DraftValidationIssue.noMateriali)));
    });

    test('flags missingCustomerSignature when customerSignatureAllegatoId null',
        () async {
      final draft =
          await _insertDraft(db, customerSignatureAllegatoId: null);

      final result = validateDraft(
        draft: draft,
        staffCount: 1,
        materialiCount: 1,
      );

      expect(
        result.issues,
        contains(DraftValidationIssue.missingCustomerSignature),
      );
    });

    test(
        'flags missingTechnicianSignature when technicianSignatureAllegatoId null',
        () async {
      final draft =
          await _insertDraft(db, technicianSignatureAllegatoId: null);

      final result = validateDraft(
        draft: draft,
        staffCount: 1,
        materialiCount: 1,
      );

      expect(
        result.issues,
        contains(DraftValidationIssue.missingTechnicianSignature),
      );
    });
  });

  // ── Multiple issues ────────────────────────────────────────────────────────

  group('validateDraft — multiple issues', () {
    test('reports all issues for a bare-minimum draft', () async {
      final draft = await _insertDraft(
        db,
        title: '',
        customerId: null,
        customerSignatureAllegatoId: null,
        technicianSignatureAllegatoId: null,
        materialiNotRequired: false,
      );

      final result = validateDraft(
        draft: draft,
        staffCount: 0,
        materialiCount: 0,
        customerFreeText: null,
      );

      expect(result.issues, hasLength(greaterThanOrEqualTo(5)));
      expect(result.issues, containsAll([
        DraftValidationIssue.missingTitle,
        DraftValidationIssue.missingCustomer,
        DraftValidationIssue.noStaff,
        DraftValidationIssue.noMateriali,
        DraftValidationIssue.missingCustomerSignature,
        DraftValidationIssue.missingTechnicianSignature,
      ]));
      expect(result.isValid, isFalse);
    });
  });

  // ── Italian messages ───────────────────────────────────────────────────────

  group('validateDraft — Italian messages', () {
    test('italianMessages returns a string per issue', () async {
      final draft = await _insertDraft(
        db,
        title: '',
        customerId: null,
        customerSignatureAllegatoId: null,
        technicianSignatureAllegatoId: null,
      );

      final result = validateDraft(
        draft: draft,
        staffCount: 0,
        materialiCount: 0,
      );

      expect(result.italianMessages.length, result.issues.length);
      expect(result.italianMessages, everyElement(isA<String>()));
    });

    test('italianMessages are non-empty strings', () async {
      final draft = await _insertDraft(db, title: '');

      final result = validateDraft(
        draft: draft,
        staffCount: 1,
        materialiCount: 1,
      );

      for (final msg in result.italianMessages) {
        expect(msg.isNotEmpty, isTrue);
      }
    });
  });
}
