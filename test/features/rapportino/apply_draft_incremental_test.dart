// dart format width=100
// test/features/rapportino/apply_draft_incremental_test.dart
//
// Task 12: the AI draft is a LIVE FEED into the ordinary rapportino. Only the confirmed subset is
// written into the local Drift report, applying is repeatable and never overwrites what the
// technician changed by hand, and every hand change goes back to the server as a confirmed edit.
//
// Harness: an in-memory Drift database (as apply_confirmed_draft_test.dart), SharedPreferences
// mocks for the per-session feed state, and a fake AiApiClient that records every edits-only sync.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tasktap_mobile/data/ai/ai_api_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/import_server_report.dart' show controlRowId;
import 'package:tasktap_mobile/features/rapportino/ai_draft_feed.dart';

const _report = 'rep-1';
const _session = 'sess-1';
const _me = '11111111-1111-1111-1111-111111111111';
const _planned = '22222222-2222-2222-2222-222222222222';
const _mat = '33333333-3333-3333-3333-333333333333';
const _ctrl = '44444444-4444-4444-4444-444444444444';

class _Sync {
  _Sync(this.edits, this.key, this.text);
  final List<Map<String, dynamic>>? edits;
  final String key;
  final String text;
}

/// Records every request; answers from [replies] (an exception is thrown), else with [draft].
class _FakeAi extends AiApiClient {
  _FakeAi() : super(Dio());

  final List<_Sync> calls = [];
  final List<Object> replies = [];
  AiCopilotDraftDto draft = AiCopilotDraftDto.empty;

  @override
  Future<AiConversationTurnResult> postTurn(
    String sessionId, {
    required String text,
    AiTurnSource source = AiTurnSource.typed,
    String? audioRef,
    String? rawTranscript,
    String? replacesTurnId,
    List<Map<String, dynamic>>? confirmedEdits,
    required String idempotencyKey,
  }) async {
    calls.add(_Sync(confirmedEdits, idempotencyKey, text));
    if (replies.isNotEmpty) {
      final r = replies.removeAt(0);
      if (r is AiConversationTurnResult) return r;
      throw r;
    }
    return AiConversationTurnResult(assistantReplyText: '', draft: draft);
  }
}

AiDraftWorkerRef _worker(
  String id, {
  double? hours,
  double? km,
  AiResolutionState state = AiResolutionState.operatorConfirmed,
  AiFactSource source = AiFactSource.operatorInput,
}) => AiDraftWorkerRef(
  userId: id,
  fullName: 'Tecnico $id',
  hours: hours,
  km: km,
  state: state,
  source: source,
);

AiDraftMaterialUsage _material(
  String id,
  double qty, {
  String name = 'Valvola',
  AiResolutionState state = AiResolutionState.operatorConfirmed,
  AiFactSource source = AiFactSource.operatorInput,
}) => AiDraftMaterialUsage(
  materialId: id,
  name: name,
  quantity: qty,
  state: state,
  source: source,
);

AiCopilotDraftDto _draft({
  List<AiDraftWorkerRef> workers = const [],
  List<AiDraftMaterialUsage> materials = const [],
  List<AiDraftControlAnswer> controlli = const [],
  List<AiCandidateFact> openItems = const [],
  String? signoff,
}) => AiCopilotDraftDto(
  customerSignoffText: signoff,
  workers: workers,
  materials: materials,
  controlli: controlli,
  activities: const [],
  openItems: openItems,
);

class _Harness {
  _Harness._(this.db, this.store, this.feed, this.ai, this.syncer);

  final AppDatabase db;
  final AiDraftFeedStore store;
  final AiDraftFeed feed;
  final _FakeAi ai;
  final AiEditSyncer syncer;

  static Future<_Harness> create() async {
    final db = AppDatabase(NativeDatabase.memory());
    await db
        .into(db.draftReports)
        .insert(
          DraftReportsCompanion.insert(
            id: _report,
            tenantId: 'ten-1',
            createdAt: DateTime.utc(2026, 10, 20),
            title: 'Rapportino',
            insertedUserId: _me,
            locationId: 'loc-1',
            // As createLocalDraft writes it: the phone's draft until the queue sends it.
            isLocalOnly: const Value(true),
          ),
        );
    final store = AiDraftFeedStore();
    final feed = AiDraftFeed(db: db, store: store);
    await store.link(sessionId: _session, reportId: _report);
    final ai = _FakeAi();
    var n = 0;
    final syncer = AiEditSyncer(
      client: ai,
      feed: feed,
      store: store,
      retryDelay: Duration.zero,
      newKey: () => 'batch-${++n}',
    );
    return _Harness._(db, store, feed, ai, syncer);
  }

  Future<List<ReportStaffTableData>> staff() => db.select(db.reportStaffTable).get();
  Future<List<ReportMaterialiData>> materials() => db.select(db.reportMateriali).get();
  Future<List<ReportControlliData>> controls() => db.select(db.reportControlli).get();
  Future<DraftReport> header() =>
      (db.select(db.draftReports)..where((r) => r.id.equals(_report))).getSingle();
}

void main() {
  late _Harness h;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    h = await _Harness.create();
  });

  tearDown(() => h.db.close());

  test('Planned_items_apply_as_proposed_not_as_done', () async {
    await h.feed.apply(
      _session,
      _draft(
        workers: [
          // The technician's own ticket time record: ResolvedBySystem from a real record.
          _worker(
            _me,
            hours: 3,
            state: AiResolutionState.resolvedBySystem,
            source: AiFactSource.ticketRecord,
          ),
          // Assigned, not confirmed: assignment is not participation.
          _worker(
            _planned,
            state: AiResolutionState.needsConfirmation,
            source: AiFactSource.planned,
          ),
        ],
        materials: [
          _material(
            _mat,
            2,
            state: AiResolutionState.needsConfirmation,
            source: AiFactSource.planned,
          ),
        ],
        controlli: const [
          AiDraftControlAnswer(ticketControlId: _ctrl, state: AiResolutionState.needsConfirmation),
        ],
      ),
    );

    final staff = await h.staff();
    expect(staff.map((s) => s.userId), [_me], reason: 'a planned worker is never written as done');
    expect(staff.single.hoursWorked, 3);
    expect(await h.materials(), isEmpty, reason: 'a planned material is never written as used');
    expect(await h.controls(), isEmpty, reason: 'a checklist question is not an answer');
    expect(await h.feed.pendingEdits(_session), isEmpty);
  });

  test('Apply_is_idempotent', () async {
    final draft = _draft(
      workers: [_worker(_me, hours: 3, km: 12)],
      materials: [_material(_mat, 2), _material('', 1, name: 'Nastro teflon')],
      controlli: const [
        AiDraftControlAnswer(
          ticketControlId: _ctrl,
          boolValue: true,
          state: AiResolutionState.operatorConfirmed,
        ),
      ],
    );
    await h.feed.apply(_session, draft);
    final s1 = await h.staff();
    final m1 = await h.materials();
    final c1 = await h.controls();

    await h.feed.apply(_session, draft);

    final s2 = await h.staff();
    final m2 = await h.materials();
    final c2 = await h.controls();
    expect(s2.map((r) => (r.id, r.userId, r.hoursWorked, r.kmTraveled)).toList(),
        s1.map((r) => (r.id, r.userId, r.hoursWorked, r.kmTraveled)).toList());
    expect(m2.map((r) => (r.id, r.materialeId, r.freeTextName, r.quantity)).toList(),
        m1.map((r) => (r.id, r.materialeId, r.freeTextName, r.quantity)).toList());
    expect(m2, hasLength(2));
    expect(c2.single.id, controlRowId(_report, _ctrl));
    expect(c2.map((r) => (r.id, r.boolValue)).toList(), c1.map((r) => (r.id, r.boolValue)).toList());
    expect(await h.feed.pendingEdits(_session), isEmpty, reason: 'nothing was edited by hand');
  });

  test('Second_apply_does_not_overwrite_a_hand_edited_field', () async {
    await h.feed.apply(_session, _draft(workers: [_worker(_me, hours: 3)]));
    final row = (await h.staff()).single;
    // The technician corrects the hours in the editor.
    await (h.db.update(h.db.reportStaffTable)..where((r) => r.id.equals(row.id))).write(
      const ReportStaffTableCompanion(hoursWorked: Value(5)),
    );

    // A later turn proposes other hours and adds km.
    await h.feed.apply(_session, _draft(workers: [_worker(_me, hours: 4, km: 20)]));

    final after = (await h.staff()).single;
    expect(after.hoursWorked, 5, reason: 'the hand edit wins over a later apply');
    expect(after.kmTraveled, 20, reason: 'a field the technician did not touch still updates');
  });

  test('Applying_never_sets_signoff_or_submits', () async {
    await h.feed.apply(
      _session,
      _draft(workers: [_worker(_me, hours: 3)], signoff: 'Il cliente ha accettato'),
    );
    final r = await h.header();
    expect(r.customerSignoffText, isNull, reason: 'sign-off is never written by an AI path');
    expect(r.customerSignatureAllegatoId, isNull);
    expect(r.technicianSignatureAllegatoId, isNull);
    expect(r.stato, 'Bozza');
    expect(r.isLocalOnly, isTrue);
    expect(r.closedAt, isNull);
    expect(r.isAiAssisted, isTrue, reason: 'provenance is written where AI data enters');
  });

  test('Hand_edit_is_sent_as_a_confirmed_edit', () async {
    await h.feed.apply(_session, _draft(workers: [_worker(_me, hours: 3)]));
    final row = (await h.staff()).single;
    await (h.db.update(h.db.reportStaffTable)..where((r) => r.id.equals(row.id))).write(
      const ReportStaffTableCompanion(hoursWorked: Value(5)),
    );

    final pending = await h.feed.pendingEdits(_session);
    expect(pending, [
      const AiConfirmedEdit(kind: 'worker', id: _me, property: 'hours', value: 5.0),
    ]);

    await h.syncer.sync(_session);
    expect(h.ai.calls.single.text, '', reason: 'an edits-only request');
    expect(h.ai.calls.single.edits, [
      {'kind': 'worker', 'id': _me, 'property': 'hours', 'value': 5.0, 'remove': false},
    ]);
    expect(await h.feed.pendingEdits(_session), isEmpty, reason: 'acknowledged once sent');
  });

  test('Hand_removal_is_sent_as_remove_true', () async {
    await h.feed.apply(_session, _draft(materials: [_material(_mat, 2)]));
    await h.db.delete(h.db.reportMateriali).go();

    expect(await h.feed.pendingEdits(_session), [
      const AiConfirmedEdit(kind: 'material', id: _mat, remove: true),
    ]);

    // Until the server has folded the removal the draft still carries the line: it must not
    // come back into the report.
    await h.feed.apply(_session, _draft(materials: [_material(_mat, 2)]));
    expect(await h.materials(), isEmpty);
  });

  test('Hand_added_line_is_sent_as_confirmed_edit', () async {
    await h.feed.apply(_session, _draft(workers: [_worker(_me, hours: 3)]));
    await h.db
        .into(h.db.reportStaffTable)
        .insert(
          ReportStaffTableCompanion.insert(
            id: 'hand-1',
            tenantId: 'ten-1',
            createdAt: DateTime.utc(2026, 10, 20),
            reportId: _report,
            userId: _planned,
            hoursWorked: const Value(2),
          ),
        );
    await h.db
        .into(h.db.reportMateriali)
        .insert(
          ReportMaterialiCompanion.insert(
            id: 'hand-2',
            tenantId: 'ten-1',
            createdAt: DateTime.utc(2026, 10, 20),
            reportId: _report,
            freeTextName: const Value('Nastro teflon'),
            quantity: 1,
          ),
        );

    final pending = await h.feed.pendingEdits(_session);
    expect(
      pending,
      containsAll([
        const AiConfirmedEdit(kind: 'worker', id: _planned),
        const AiConfirmedEdit(kind: 'worker', id: _planned, property: 'hours', value: 2.0),
        const AiConfirmedEdit(kind: 'material', name: 'Nastro teflon'),
        const AiConfirmedEdit(
          kind: 'material',
          name: 'Nastro teflon',
          property: 'quantity',
          value: 1.0,
        ),
      ]),
    );
    expect(pending, hasLength(4));

    // The server confirms the hand-added worker with other hours: the hand line is the
    // technician's and is never overwritten; nothing is duplicated.
    await h.syncer.sync(_session);
    await h.feed.apply(
      _session,
      _draft(workers: [_worker(_me, hours: 3), _worker(_planned, hours: 7)]),
    );
    final staff = await h.staff();
    expect(staff, hasLength(2));
    expect(staff.firstWhere((s) => s.userId == _planned).hoursWorked, 2);
  });

  test('Accepting_a_proposal_sends_a_property_less_edit', () async {
    final planned = _material(
      _mat,
      2,
      state: AiResolutionState.needsConfirmation,
      source: AiFactSource.planned,
    );
    await h.feed.apply(_session, _draft(materials: [planned]));
    expect(await h.materials(), isEmpty);

    h.ai.draft = _draft(materials: [_material(_mat, 2)]);
    final returned = await h.syncer.sync(
      _session,
      extra: [AiEditSyncer.acceptMaterial(planned)],
    );

    expect(h.ai.calls.single.edits, [
      {'kind': 'material', 'id': _mat, 'remove': false},
    ]);
    expect(h.ai.calls.single.text, '');
    expect(returned, isNotNull);

    // Once the server returns it as confirmed, the next incremental apply writes it.
    await h.feed.apply(_session, returned!);
    expect((await h.materials()).single.quantity, 2);
    expect(await h.feed.pendingEdits(_session), isEmpty);
  });

  test('Edit_batch_retry_reuses_the_idempotency_key', () async {
    await h.feed.apply(_session, _draft(workers: [_worker(_me, hours: 3)]));
    final row = (await h.staff()).single;
    await (h.db.update(h.db.reportStaffTable)..where((r) => r.id.equals(row.id))).write(
      const ReportStaffTableCompanion(hoursWorked: Value(5)),
    );

    h.ai.replies.add(
      const AiConversationException(null, 'Nessuna connessione.', offline: true),
    );
    await expectLater(h.syncer.sync(_session), throwsA(isA<AiConversationException>()));

    // Meanwhile the technician edits again: the unacknowledged batch is resent first, exactly.
    await (h.db.update(h.db.reportStaffTable)..where((r) => r.id.equals(row.id))).write(
      const ReportStaffTableCompanion(kmTraveled: Value(30)),
    );
    // A fresh syncer (as after an app restart) still finds the persisted batch.
    var n = 100;
    final restarted = AiEditSyncer(
      client: h.ai,
      feed: h.feed,
      store: h.store,
      retryDelay: Duration.zero,
      newKey: () => 'batch-${++n}',
    );
    await restarted.sync(_session);

    expect(h.ai.calls.map((c) => c.key).toList(), ['batch-1', 'batch-1', 'batch-101']);
    expect(h.ai.calls[1].edits, h.ai.calls[0].edits, reason: 'a retry is the same body');
    expect(h.ai.calls[2].edits, [
      {'kind': 'worker', 'id': _me, 'property': 'km', 'value': 30.0, 'remove': false},
    ]);
    expect(await h.feed.pendingEdits(_session), isEmpty);
  });

  test('Edits_over_the_batch_limit_are_split', () async {
    // The ticket's 60 checklist questions are in the draft (seeded, unanswered); the technician
    // answers all of them by hand: 60 edits, over the server's 50-per-request cap.
    String controlId(int i) => '55555555-5555-5555-5555-${i.toString().padLeft(12, '0')}';
    await h.feed.apply(
      _session,
      _draft(
        controlli: [
          for (var i = 0; i < 60; i++)
            AiDraftControlAnswer(
              ticketControlId: controlId(i),
              state: AiResolutionState.needsConfirmation,
            ),
        ],
      ),
    );
    for (var i = 0; i < 60; i++) {
      final id = controlId(i);
      await h.db
          .into(h.db.reportControlli)
          .insert(
            ReportControlliCompanion.insert(
              id: controlRowId(_report, id),
              tenantId: 'ten-1',
              createdAt: DateTime.utc(2026, 10, 20),
              reportId: _report,
              controlId: id,
              boolValue: const Value(true),
            ),
          );
    }
    await h.syncer.sync(_session);

    expect(h.ai.calls.map((c) => c.edits!.length).toList(), [50, 10]);
    expect(h.ai.calls.map((c) => c.key).toSet(), hasLength(2), reason: 'one key per batch');
    expect(await h.feed.pendingEdits(_session), isEmpty);
  });

  test('an answer to a control the AI draft does not hold (asset checklist) is never sent', () async {
    await h.feed.apply(_session, _draft());
    await h.db
        .into(h.db.reportControlli)
        .insert(
          ReportControlliCompanion.insert(
            id: controlRowId(_report, _ctrl),
            tenantId: 'ten-1',
            createdAt: DateTime.utc(2026, 10, 20),
            reportId: _report,
            controlId: _ctrl,
            boolValue: const Value(true),
          ),
        );
    expect(await h.feed.pendingEdits(_session), isEmpty);
  });

  test('Draft_too_large_stops_syncing_with_an_italian_message', () async {
    await h.feed.apply(_session, _draft(workers: [_worker(_me, hours: 3)]));
    await h.db.delete(h.db.reportStaffTable).go();
    h.ai.replies.add(const AiConversationException(409, 'x', code: 'draft_too_large'));

    await expectLater(
      h.syncer.sync(_session),
      throwsA(
        isA<AiEditSyncBlockedException>().having((e) => e.message, 'message', contains('limite')),
      ),
    );
    // Retrying cannot help: later syncs and turns send nothing.
    expect(await h.syncer.sync(_session), isNull);
    expect(await h.syncer.editsForTurn(_session), isEmpty);
    expect(h.ai.calls, hasLength(1));
  });

  test('Edits_ride_in_the_next_turn_and_are_acknowledged_with_it', () async {
    await h.feed.apply(_session, _draft(workers: [_worker(_me, hours: 3)]));
    await h.db.delete(h.db.reportStaffTable).go();

    final forTurn = await h.syncer.editsForTurn(_session);
    expect(forTurn, [const AiConfirmedEdit(kind: 'worker', id: _me, remove: true)]);
    expect(h.ai.calls, isEmpty, reason: 'they ride in the turn itself, no separate request');

    await h.syncer.acknowledge(_session, forTurn);
    expect(await h.feed.pendingEdits(_session), isEmpty);
  });

  test('Confirm_after_incremental_apply_creates_no_duplicates', () async {
    await h.feed.apply(
      _session,
      _draft(
        workers: [_worker(_me, hours: 3)],
        materials: [_material(_mat, 2), _material('', 1, name: 'Nastro teflon')],
      ),
    );
    final row = (await h.staff()).single;
    await (h.db.update(h.db.reportStaffTable)..where((r) => r.id.equals(row.id))).write(
      const ReportStaffTableCompanion(hoursWorked: Value(5)),
    );

    await h.feed.applyConfirmResponse(
      _session,
      const AiConversationConfirmResponse(
        title: 'Sostituzione valvola',
        staff: [AiResolvedStaff(userId: _me, hoursWorked: 3)],
        materials: [
          AiResolvedMaterial(materialeId: _mat, quantity: 2),
          AiResolvedMaterial(
            freeTextName: 'Nastro teflon',
            quantity: 1,
            notes: 'Da verificare: materiale non trovato a catalogo.',
          ),
        ],
        controlli: [AiResolvedControl(ticketControlId: _ctrl, boolValue: true)],
      ),
    );

    final staff = await h.staff();
    expect(staff, hasLength(1));
    expect(staff.single.hoursWorked, 5, reason: 'Confirm respects the hand edit too');
    expect(await h.materials(), hasLength(2));
    expect((await h.controls()).single.id, controlRowId(_report, _ctrl));
  });

  test('Held_removal_can_be_re_added_or_kept_removed', () async {
    await h.feed.apply(_session, _draft(materials: [_material(_mat, 2)]));
    await h.db.delete(h.db.reportMateriali).go();
    await h.syncer.sync(_session); // the removal is confirmed on the server

    const held = AiCandidateFact(
      field: 'removed.materials.id:$_mat',
      state: AiResolutionState.conflict,
      conflictOperatorValue: 'Valvola',
    );

    // Mantieni rimosso: a removal edit that settles the hold.
    await h.syncer.resolveHeldRemoval(_session, held, reAdd: false);
    expect(h.ai.calls.last.edits, [
      {'kind': 'material', 'id': _mat, 'remove': true},
    ]);

    // Reinserisci: a hand re-add by id and name; the line comes back on the next apply.
    h.ai.draft = _draft(materials: [_material(_mat, 2)]);
    final returned = await h.syncer.resolveHeldRemoval(_session, held, reAdd: true);
    expect(h.ai.calls.last.edits, [
      {'kind': 'material', 'id': _mat, 'name': 'Valvola', 'remove': false},
    ]);
    await h.feed.apply(_session, returned!);
    expect((await h.materials()).single.materialeId, _mat);
    expect(await h.feed.pendingEdits(_session), isEmpty);
  });

  test('a held removal of a control can only be kept removed', () {
    const held = AiCandidateFact(
      field: 'removed.controlli.id:$_ctrl',
      state: AiResolutionState.conflict,
    );
    expect(AiEditSyncer.heldRemovalEdit(held, reAdd: true), isNull);
    expect(
      AiEditSyncer.heldRemovalEdit(held, reAdd: false),
      const AiConfirmedEdit(kind: 'control', id: _ctrl, remove: true),
    );
  });

  test('an unlinked session applies nothing and has no edits', () async {
    expect(await h.feed.apply('other', _draft(workers: [_worker(_me, hours: 3)])), isFalse);
    expect(await h.staff(), isEmpty);
    expect(await h.syncer.editsForTurn('other'), isEmpty);
  });
}
