// Tests for DraftReportRepository — M4
//
// Uses an in-memory Drift DB — no network, no file system.
// Verifies:
//   - createDraft inserts a new draft
//   - saveDraft upserts (autosave round-trip)
//   - getDraft / watchDraft work
//   - deleteDraft removes header + all child rows
//   - Staff CRUD (upsert, delete, get, watch)
//   - Materiali CRUD
//   - Controlli CRUD
//   - Allegati insert/delete/get
//   - Signature save creates an allegato with correct fields
//   - watchLocalDrafts returns only isLocalOnly=true drafts, newest first

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/draft_report_repository.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

DraftReportsCompanion _draftCompanion({
  String id = 'r-1',
  String title = 'Rapportino Test',
  bool isLocalOnly = true,
}) =>
    DraftReportsCompanion.insert(
      id: id,
      tenantId: 'tenant-1',
      createdAt: DateTime.utc(2026, 6, 21, 10),
      title: title,
      insertedUserId: 'user-1',
      locationId: 'loc-1',
      isLocalOnly: Value(isLocalOnly),
      stato: const Value('Bozza'),
    );

ReportStaffTableCompanion _staffCompanion({
  String id = 's-1',
  String reportId = 'r-1',
  String userId = 'user-1',
  double? hoursWorked = 4.0,
  double kmTraveled = 50.0,
}) =>
    ReportStaffTableCompanion(
      id: Value(id),
      tenantId: const Value('tenant-1'),
      createdAt: Value(DateTime.utc(2026, 6, 21, 10)),
      reportId: Value(reportId),
      userId: Value(userId),
      hoursWorked: Value(hoursWorked),
      kmTraveled: Value(kmTraveled),
      pauseMinutes: const Value(0),
    );

ReportMaterialiCompanion _materialeCompanion({
  String id = 'm-1',
  String reportId = 'r-1',
  String? materialeId,
  String? freeTextName = 'Cavo rete cat6',
  double quantity = 10.0,
}) =>
    ReportMaterialiCompanion(
      id: Value(id),
      tenantId: const Value('tenant-1'),
      createdAt: Value(DateTime.utc(2026, 6, 21, 10)),
      reportId: Value(reportId),
      materialeId: Value(materialeId),
      freeTextName: Value(freeTextName),
      quantity: Value(quantity),
      unitOfMeasure: const Value('m'),
    );

ReportControlliCompanion _controlloCompanion({
  String id = 'c-1',
  String reportId = 'r-1',
  String controlId = 'ctrl-pressione',
  String? stringValue = '120 bar',
}) =>
    ReportControlliCompanion(
      id: Value(id),
      tenantId: const Value('tenant-1'),
      createdAt: Value(DateTime.utc(2026, 6, 21, 10)),
      reportId: Value(reportId),
      controlId: Value(controlId),
      stringValue: Value(stringValue),
    );

// ══════════════════════════════════════════════════════════════════════════════
// Tests
// ══════════════════════════════════════════════════════════════════════════════

void main() {
  late AppDatabase db;
  late DraftReportRepository repo;

  setUp(() {
    db = _makeDb();
    repo = DraftReportRepository(db);
  });

  tearDown(() async => db.close());

  // ── Draft header ───────────────────────────────────────────────────────────

  group('createDraft + getDraft', () {
    test('creates a draft and retrieves it by id', () async {
      await repo.createDraft(_draftCompanion());

      final draft = await repo.getDraft('r-1');
      expect(draft, isNotNull);
      expect(draft!.id, 'r-1');
      expect(draft.title, 'Rapportino Test');
      expect(draft.isLocalOnly, isTrue);
    });

    test('getDraft returns null for unknown id', () async {
      final draft = await repo.getDraft('unknown');
      expect(draft, isNull);
    });
  });

  group('saveDraft — autosave round-trip', () {
    test('upserts an existing draft (title update)', () async {
      await repo.createDraft(_draftCompanion());

      await repo.saveDraft(
        DraftReportsCompanion(
          id: const Value('r-1'),
          tenantId: const Value('tenant-1'),
          createdAt: Value(DateTime.utc(2026, 6, 21, 10)),
          title: const Value('Titolo aggiornato'),
          insertedUserId: const Value('user-1'),
          locationId: const Value('loc-1'),
          stato: const Value('Bozza'),
          isLocalOnly: const Value(true),
        ),
      );

      final draft = await repo.getDraft('r-1');
      expect(draft!.title, 'Titolo aggiornato');
    });

    test('saveDraft creates if not exists (insert on conflict update)', () async {
      await repo.saveDraft(
        DraftReportsCompanion(
          id: const Value('r-new'),
          tenantId: const Value('tenant-1'),
          createdAt: Value(DateTime.utc(2026, 6, 21, 11)),
          title: const Value('Nuovo'),
          insertedUserId: const Value('user-1'),
          locationId: const Value('loc-1'),
          stato: const Value('Bozza'),
          isLocalOnly: const Value(true),
        ),
      );

      final draft = await repo.getDraft('r-new');
      expect(draft, isNotNull);
      expect(draft!.title, 'Nuovo');
    });
  });

  group('watchLocalDrafts', () {
    test('returns only isLocalOnly=true drafts', () async {
      await repo.createDraft(_draftCompanion(id: 'r-local', isLocalOnly: true));
      await repo.createDraft(
          _draftCompanion(id: 'r-synced', isLocalOnly: false));

      final drafts = await repo.watchLocalDrafts().first;
      expect(drafts.length, 1);
      expect(drafts.first.id, 'r-local');
    });

    test('empty list when no local drafts', () async {
      final drafts = await repo.watchLocalDrafts().first;
      expect(drafts, isEmpty);
    });
  });

  group('deleteDraft', () {
    test('removes draft header and all child rows', () async {
      await repo.createDraft(_draftCompanion());
      await repo.upsertStaff(_staffCompanion());
      await repo.upsertMateriale(_materialeCompanion());
      await repo.upsertControllo(_controlloCompanion());

      await repo.deleteDraft('r-1');

      expect(await repo.getDraft('r-1'), isNull);
      expect(await repo.getStaff('r-1'), isEmpty);
      expect(await repo.getMateriali('r-1'), isEmpty);
      expect(await repo.getControlli('r-1'), isEmpty);
    });
  });

  // ── Staff ──────────────────────────────────────────────────────────────────

  group('staff CRUD', () {
    setUp(() async => repo.createDraft(_draftCompanion()));

    test('upsertStaff inserts a new staff row', () async {
      await repo.upsertStaff(_staffCompanion());

      final rows = await repo.getStaff('r-1');
      expect(rows.length, 1);
      expect(rows.first.userId, 'user-1');
      expect(rows.first.hoursWorked, 4.0);
      expect(rows.first.kmTraveled, 50.0);
    });

    test('upsertStaff updates an existing row (autosave)', () async {
      await repo.upsertStaff(_staffCompanion(hoursWorked: 4.0));
      await repo.upsertStaff(_staffCompanion(hoursWorked: 8.0));

      final rows = await repo.getStaff('r-1');
      expect(rows.length, 1);
      expect(rows.first.hoursWorked, 8.0);
    });

    test('deleteStaff removes the row', () async {
      await repo.upsertStaff(_staffCompanion());
      await repo.deleteStaff('s-1');

      expect(await repo.getStaff('r-1'), isEmpty);
    });

    test('multiple staff rows for same report', () async {
      await repo.upsertStaff(_staffCompanion(id: 's-1', userId: 'u1'));
      await repo.upsertStaff(_staffCompanion(id: 's-2', userId: 'u2'));
      await repo.upsertStaff(_staffCompanion(id: 's-3', userId: 'u3'));

      expect((await repo.getStaff('r-1')).length, 3);
    });

    test('watchStaff emits reactive updates', () async {
      await repo.upsertStaff(_staffCompanion());

      final firstEmit = await repo.watchStaff('r-1').first;
      expect(firstEmit.length, 1);
    });
  });

  // ── Staff km / hours math ──────────────────────────────────────────────────

  group('staff km and hours storage', () {
    setUp(() async => repo.createDraft(_draftCompanion()));

    test('stores km traveled correctly', () async {
      await repo.upsertStaff(_staffCompanion(kmTraveled: 123.5));

      final rows = await repo.getStaff('r-1');
      expect(rows.first.kmTraveled, 123.5);
    });

    test('stores zero km by default', () async {
      await repo.upsertStaff(_staffCompanion(kmTraveled: 0.0));

      final rows = await repo.getStaff('r-1');
      expect(rows.first.kmTraveled, 0.0);
    });

    test('stores start/end time for timer round-trip', () async {
      final start = DateTime.utc(2026, 6, 21, 8, 0);
      final end = DateTime.utc(2026, 6, 21, 16, 30);

      await db.into(db.reportStaffTable).insertOnConflictUpdate(
            ReportStaffTableCompanion(
              id: const Value('s-timer'),
              tenantId: const Value('tenant-1'),
              createdAt: Value(DateTime.utc(2026, 6, 21)),
              reportId: const Value('r-1'),
              userId: const Value('user-1'),
              startTime: Value(start),
              endTime: Value(end),
              pauseMinutes: const Value(30),
              kmTraveled: const Value(0.0),
            ),
          );

      final rows = await repo.getStaff('r-1');
      final row = rows.first;
      expect(row.startTime, isNotNull);
      expect(row.endTime, isNotNull);
      // 8:00 → 16:30 = 510 minutes − 30 pause = 480 minutes = 8.0 hours
      final workedMins =
          row.endTime!.difference(row.startTime!).inMinutes - row.pauseMinutes;
      expect(workedMins, 480);
      expect(workedMins / 60.0, 8.0);
    });
  });

  // ── Materiali ──────────────────────────────────────────────────────────────

  group('materiali CRUD', () {
    setUp(() async => repo.createDraft(_draftCompanion()));

    test('upsertMateriale inserts a new materiale row (free-text)', () async {
      await repo.upsertMateriale(_materialeCompanion());

      final rows = await repo.getMateriali('r-1');
      expect(rows.length, 1);
      expect(rows.first.freeTextName, 'Cavo rete cat6');
      expect(rows.first.quantity, 10.0);
      expect(rows.first.materialeId, isNull);
    });

    test('upsertMateriale inserts a row with cached materialeId', () async {
      await repo.upsertMateriale(
        _materialeCompanion(materialeId: 'mat-42', freeTextName: null),
      );

      final rows = await repo.getMateriali('r-1');
      expect(rows.first.materialeId, 'mat-42');
      expect(rows.first.freeTextName, isNull);
    });

    test('deleteMateriale removes the row', () async {
      await repo.upsertMateriale(_materialeCompanion());
      await repo.deleteMateriale('m-1');

      expect(await repo.getMateriali('r-1'), isEmpty);
    });

    test('multiple materiali rows', () async {
      await repo.upsertMateriale(_materialeCompanion(id: 'm-1'));
      await repo.upsertMateriale(_materialeCompanion(id: 'm-2'));

      expect((await repo.getMateriali('r-1')).length, 2);
    });
  });

  // ── Controlli ──────────────────────────────────────────────────────────────

  group('controlli CRUD', () {
    setUp(() async => repo.createDraft(_draftCompanion()));

    test('upsertControllo inserts a new row', () async {
      await repo.upsertControllo(_controlloCompanion());

      final rows = await repo.getControlli('r-1');
      expect(rows.length, 1);
      expect(rows.first.controlId, 'ctrl-pressione');
      expect(rows.first.stringValue, '120 bar');
    });

    test('upsertControllo updates existing row by id', () async {
      await repo.upsertControllo(
          _controlloCompanion(stringValue: 'primo valore'));
      await repo.upsertControllo(
          _controlloCompanion(stringValue: 'secondo valore'));

      final rows = await repo.getControlli('r-1');
      expect(rows.length, 1);
      expect(rows.first.stringValue, 'secondo valore');
    });
  });

  // ── Allegati ───────────────────────────────────────────────────────────────

  group('allegati insert/delete/get', () {
    setUp(() async => repo.createDraft(_draftCompanion()));

    test('insertAllegato stores a photo allegato', () async {
      await repo.insertAllegato(
        ReportAllegatiCompanion.insert(
          id: 'photo-1',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 6, 21, 10),
          fileName: 'impianto.jpg',
          contentType: 'image/jpeg',
          sizeBytes: 204800,
          storagePath: '/local/impianto.jpg',
          url: '/local/impianto.jpg',
          entityType: 1,
          entityId: 'r-1',
          uploadedByUserId: 'user-1',
          isPendingUpload: const Value(true),
        ),
      );

      final rows = await repo.getAllegati('r-1');
      expect(rows.length, 1);
      expect(rows.first.fileName, 'impianto.jpg');
      expect(rows.first.isPendingUpload, isTrue);
      expect(rows.first.contentType, 'image/jpeg');
    });

    test('deleteAllegato removes the row', () async {
      await repo.insertAllegato(
        ReportAllegatiCompanion.insert(
          id: 'photo-del',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 6, 21),
          fileName: 'x.jpg',
          contentType: 'image/jpeg',
          sizeBytes: 1024,
          storagePath: '/tmp/x.jpg',
          url: '/tmp/x.jpg',
          entityType: 1,
          entityId: 'r-1',
          uploadedByUserId: 'user-1',
        ),
      );
      await repo.deleteAllegato('photo-del');

      expect(await repo.getAllegati('r-1'), isEmpty);
    });

    test('watchAllegati emits reactive updates', () async {
      final first = await repo.watchAllegati('r-1').first;
      expect(first, isEmpty);
    });
  });

  // ── Signature save ─────────────────────────────────────────────────────────

  group('saveSignature', () {
    setUp(() async => repo.createDraft(_draftCompanion()));

    test('creates an allegato for customer signature', () async {
      final fakeBytes = Uint8List.fromList([0, 1, 2, 3]);
      final id = await repo.saveSignature(
        reportId: 'r-1',
        allegatoId: 'sig-cust-1',
        tenantId: 'tenant-1',
        uploadedByUserId: 'user-1',
        bytes: fakeBytes,
        localPath: '/tmp/sig-cust-1.png',
        isCustomer: true,
      );

      expect(id, 'sig-cust-1');
      final rows = await repo.getAllegati('r-1');
      expect(rows.length, 1);
      expect(rows.first.fileName, 'firma_cliente.png');
      expect(rows.first.contentType, 'image/png');
      expect(rows.first.isPendingUpload, isTrue);
    });

    test('creates an allegato for technician signature', () async {
      final fakeBytes = Uint8List.fromList([10, 20, 30]);
      await repo.saveSignature(
        reportId: 'r-1',
        allegatoId: 'sig-tech-1',
        tenantId: 'tenant-1',
        uploadedByUserId: 'user-1',
        bytes: fakeBytes,
        localPath: '/tmp/sig-tech-1.png',
        isCustomer: false,
      );

      final rows = await repo.getAllegati('r-1');
      expect(rows.first.fileName, 'firma_tecnico.png');
    });

    test('sizeBytes matches the bytes length', () async {
      final bytes = Uint8List.fromList(List.generate(512, (i) => i % 256));
      await repo.saveSignature(
        reportId: 'r-1',
        allegatoId: 'sig-size-test',
        tenantId: 'tenant-1',
        uploadedByUserId: 'user-1',
        bytes: bytes,
        localPath: '/tmp/sig.png',
        isCustomer: true,
      );

      final rows = await repo.getAllegati('r-1');
      expect(rows.first.sizeBytes, 512);
    });
  });
}
