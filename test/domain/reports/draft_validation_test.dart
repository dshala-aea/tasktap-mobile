// Tests for DraftValidation — M4
//
// Verifies that local validation mirrors server ReportStateMachine rules:
//   - Missing title → flagged
//   - Missing customer (no id AND no freeText) → flagged
//   - No staff → flagged
//   - No materiali AND materialiNotRequired=false → flagged
//   - No materiali but materialiNotRequired=true → OK
//   - Missing customer firma → flagged unless an absence reason is recorded
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
  // Defaults to a ticket-linked draft — every test in this file predates the cantiere-only
  // rapportino flow and was written assuming a ticket (and therefore a customer sign-off step)
  // is always present. Only the "no ticketId" group below overrides this to null.
  String? ticketId = 'ticket-1',
  String? customerSignatureAllegatoId = 'sig-cust-1',
  // Raw wire value of `CustomerSignatureAbsenceReason` (0 = assente, 1 = rifiuta, 2 = altro),
  // exactly as the Drift column stores it. Null means "nothing recorded".
  int? customerSignatureAbsenceReason,
  String? technicianSignatureAllegatoId = 'sig-tech-1',
  // Defaults to a real location, so every existing fixture keeps passing: only a test that opts
  // into `locationId: ''` exercises the missing-location check (mirrors what applyConfirmedDraft
  // writes for a confirm response whose locationId is null).
  String locationId = 'loc-1',
  bool materialiNotRequired = false,
}) async {
  await db
      .into(db.draftReports)
      .insert(
        DraftReportsCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 6, 21),
          title: title,
          insertedUserId: 'user-1',
          locationId: locationId,
          customerId: Value(customerId),
          ticketId: Value(ticketId),
          customerSignatureAllegatoId: Value(customerSignatureAllegatoId),
          customerSignatureAbsenceReason: Value(customerSignatureAbsenceReason),
          technicianSignatureAllegatoId: Value(technicianSignatureAllegatoId),
          materialiNotRequired: Value(materialiNotRequired),
          isLocalOnly: const Value(true),
        ),
      );
  return (db.select(db.draftReports)..where((r) => r.id.equals(id))).getSingle();
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

      final result = validateDraft(draft: draft, staffCount: 1, materialiCount: 1);

      expect(result.isValid, isTrue);
      expect(result.issues, isEmpty);
      expect(result.isReadyToSubmit, isTrue);
    });

    test('isValid when materialiNotRequired=true and no materiali', () async {
      final draft = await _insertDraft(db, materialiNotRequired: true);

      final result = validateDraft(draft: draft, staffCount: 1, materialiCount: 0);

      expect(result.isValid, isTrue);
    });
  });

  // ── Individual missing requirements ───────────────────────────────────────

  group('validateDraft — individual requirements', () {
    test('flags missingTitle when title is empty', () async {
      final draft = await _insertDraft(db, title: '   ');

      final result = validateDraft(draft: draft, staffCount: 1, materialiCount: 1);

      expect(result.issues, contains(DraftValidationIssue.missingTitle));
    });

    test('flags missingTitle when title is blank', () async {
      final draft = await _insertDraft(db, title: '');

      final result = validateDraft(draft: draft, staffCount: 1, materialiCount: 1);

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

    test('does NOT flag missingCustomer when customerFreeText is provided', () async {
      final draft = await _insertDraft(db, customerId: null);

      final result = validateDraft(
        draft: draft,
        staffCount: 1,
        materialiCount: 1,
        customerFreeText: 'ACME srl',
      );

      expect(result.issues, isNot(contains(DraftValidationIssue.missingCustomer)));
    });

    test('does NOT flag missingCustomer when customerId is set', () async {
      final draft = await _insertDraft(db, customerId: 'cust-1');

      final result = validateDraft(draft: draft, staffCount: 1, materialiCount: 1);

      expect(result.issues, isNot(contains(DraftValidationIssue.missingCustomer)));
    });

    test('flags noStaff when staffCount == 0', () async {
      final draft = await _insertDraft(db);

      final result = validateDraft(draft: draft, staffCount: 0, materialiCount: 1);

      expect(result.issues, contains(DraftValidationIssue.noStaff));
    });

    test('does NOT flag noStaff when staffCount > 0', () async {
      final draft = await _insertDraft(db);

      final result = validateDraft(draft: draft, staffCount: 2, materialiCount: 1);

      expect(result.issues, isNot(contains(DraftValidationIssue.noStaff)));
    });

    test('flags noMateriali when materialiCount == 0 and materialiNotRequired = false', () async {
      final draft = await _insertDraft(db, materialiNotRequired: false);

      final result = validateDraft(draft: draft, staffCount: 1, materialiCount: 0);

      expect(result.issues, contains(DraftValidationIssue.noMateriali));
    });

    test('does NOT flag noMateriali when materialiNotRequired = true and count = 0', () async {
      final draft = await _insertDraft(db, materialiNotRequired: true);

      final result = validateDraft(draft: draft, staffCount: 1, materialiCount: 0);

      expect(result.issues, isNot(contains(DraftValidationIssue.noMateriali)));
    });

    test('flags a missing customer signature when no reason is recorded', () async {
      final draft = await _insertDraft(
        db,
        customerSignatureAllegatoId: null,
        technicianSignatureAllegatoId: 'sig-tech-1',
      );

      final result = validateDraft(draft: draft, staffCount: 1, materialiCount: 1);

      expect(result.issues, contains(DraftValidationIssue.missingCustomerSignature));
      expect(result.issues, isNot(contains(DraftValidationIssue.missingTechnicianSignature)));
      expect(
        result.isReadyToSubmit,
        isFalse,
        reason:
            'an unsigned report is only submittable once "Il cliente non può firmare" records why; '
            'otherwise it is filed with no explanation at all',
      );
    });

    test('flags missingTechnicianSignature when technicianSignatureAllegatoId null', () async {
      final draft = await _insertDraft(db, technicianSignatureAllegatoId: null);

      final result = validateDraft(draft: draft, staffCount: 1, materialiCount: 1);

      expect(result.issues, contains(DraftValidationIssue.missingTechnicianSignature));
    });
  });

  // ── ticketId gates the technician-signature requirement (cantiere-only rapportini) ──
  //
  // Mirrors the backend's identical TicketId.HasValue gate: a cantiere worklog-derived report has
  // no customer-facing sign-off step, so a signature nobody is ever asked to capture must not
  // strand it in "not ready to submit" forever.

  group('validateDraft — ticketId gates the signature requirement', () {
    test('does not flag a missing technician signature when the draft has no ticketId', () async {
      final draft = await _insertDraft(
        db,
        ticketId: null,
        customerSignatureAllegatoId: null,
        technicianSignatureAllegatoId: null,
      );

      final result = validateDraft(draft: draft, staffCount: 1, materialiCount: 1);

      expect(result.issues, isNot(contains(DraftValidationIssue.missingTechnicianSignature)));
    });

    test('flags a missing technician signature when the draft has a ticketId', () async {
      final draft = await _insertDraft(
        db,
        ticketId: 'ticket-1',
        customerSignatureAllegatoId: null,
        technicianSignatureAllegatoId: null,
      );

      final result = validateDraft(draft: draft, staffCount: 1, materialiCount: 1);

      expect(result.issues, contains(DraftValidationIssue.missingTechnicianSignature));
    });
  });

  // ── Customer signature OR documented absence ("Il cliente non può firmare") ──
  //
  // A ticket-linked report may go out unsigned only when the technician recorded why. The reason
  // is what replaces the signature; without either, the report has no customer sign-off evidence
  // at all.

  group('validateDraft — customer signature or documented absence', () {
    test('an unsigned ticket-linked draft WITH a reason passes', () async {
      final draft = await _insertDraft(
        db,
        customerSignatureAllegatoId: null,
        customerSignatureAbsenceReason: 0, // Assente
        technicianSignatureAllegatoId: 'sig-tech-1',
      );

      final result = validateDraft(draft: draft, staffCount: 1, materialiCount: 1);

      expect(result.issues, isNot(contains(DraftValidationIssue.missingCustomerSignature)));
      expect(result.isReadyToSubmit, isTrue);
    });

    test('an unsigned ticket-linked draft WITHOUT a reason still fails', () async {
      final draft = await _insertDraft(
        db,
        customerSignatureAllegatoId: null,
        technicianSignatureAllegatoId: 'sig-tech-1',
      );

      final result = validateDraft(draft: draft, staffCount: 1, materialiCount: 1);

      expect(result.issues, contains(DraftValidationIssue.missingCustomerSignature));
      expect(result.isReadyToSubmit, isFalse);
    });

    test('a customer signature needs no reason', () async {
      final draft = await _insertDraft(
        db,
        customerSignatureAllegatoId: 'sig-cust-1',
        technicianSignatureAllegatoId: 'sig-tech-1',
      );

      final result = validateDraft(draft: draft, staffCount: 1, materialiCount: 1);

      expect(result.issues, isNot(contains(DraftValidationIssue.missingCustomerSignature)));
    });

    test('a cantiere-only draft (no ticket) needs neither', () async {
      final draft = await _insertDraft(
        db,
        ticketId: null,
        customerSignatureAllegatoId: null,
        technicianSignatureAllegatoId: null,
      );

      final result = validateDraft(draft: draft, staffCount: 1, materialiCount: 1);

      expect(result.issues, isNot(contains(DraftValidationIssue.missingCustomerSignature)));
    });
  });

  // ── Multiple issues ────────────────────────────────────────────────────────

  group('validateDraft — multiple issues', () {
    test('reports all issues for a bare-minimum draft', () async {
      final draft = await _insertDraft(
        db,
        title: '',
        // Overrides the fixture's real default location: "bare minimum" has to be genuinely bare
        // for the missingLocation expectation below to hold.
        locationId: '',
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
      expect(
        result.issues,
        containsAll([
          DraftValidationIssue.missingTitle,
          DraftValidationIssue.missingLocation,
          DraftValidationIssue.missingCustomer,
          DraftValidationIssue.noStaff,
          DraftValidationIssue.noMateriali,
          DraftValidationIssue.missingCustomerSignature,
          DraftValidationIssue.missingTechnicianSignature,
        ]),
        reason:
            'no signature and no recorded reason: the customer-signature rule reports its own '
            'issue instead of being folded into the technician one',
      );
      expect(result.isValid, isFalse);
    });
  });

  // ── Location ───────────────────────────────────────────────────────────────

  group('validateDraft — location', () {
    test('a draft with no location is rejected', () async {
      final draft = await _insertDraft(db, locationId: ''); // as applyConfirmedDraft writes a null one

      final result = validateDraft(
        draft: draft,
        staffCount: 1,
        materialiCount: 1,
        customerFreeText: '',
      );

      expect(result.isValid, isFalse);
      expect(result.issues, contains(DraftValidationIssue.missingLocation));
      expect(
        result.italianMessages,
        contains('Sede non specificata'),
        reason:
            'the Riepilogo step renders italianMessages verbatim; a missing string here is a '
            'blank line in front of the technician',
      );
    });

    test('a blank location does not hide the other problems', () async {
      final draft = await _insertDraft(
        db,
        title: '',
        locationId: '',
        materialiNotRequired: false,
      );

      final result = validateDraft(
        draft: draft,
        staffCount: 0,
        materialiCount: 0,
        customerFreeText: null,
      );

      expect(
        result.issues,
        containsAll([
          DraftValidationIssue.missingTitle,
          DraftValidationIssue.missingLocation,
          DraftValidationIssue.noStaff,
        ]),
        reason: 'the check appends and continues, like every other one in this function',
      );
    });

    test('a location of only whitespace counts as missing', () async {
      final draft = await _insertDraft(db, locationId: '   ');

      final result = validateDraft(draft: draft, staffCount: 1, materialiCount: 1);

      expect(result.issues, contains(DraftValidationIssue.missingLocation));
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

      final result = validateDraft(draft: draft, staffCount: 0, materialiCount: 0);

      expect(result.italianMessages.length, result.issues.length);
      expect(result.italianMessages, everyElement(isA<String>()));
    });

    test('italianMessages are non-empty strings', () async {
      final draft = await _insertDraft(db, title: '');

      final result = validateDraft(draft: draft, staffCount: 1, materialiCount: 1);

      for (final msg in result.italianMessages) {
        expect(msg.isNotEmpty, isTrue);
      }
    });
  });
}
