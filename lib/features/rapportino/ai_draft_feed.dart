// dart format width=100
import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../data/ai/ai_api_client.dart';
import '../../data/local/app_database.dart';
import '../../data/reports/import_server_report.dart' show controlRowId;
import '../../data/reports/draft_report_repository.dart';
import '../../data/sync/draft_submission_state.dart';
import '../../data/sync/sync_service.dart' show appDatabaseProvider;
import 'ai_strumenti_write.dart' show AiStrumentoLine, writeAiStrumenti;

// ══════════════════════════════════════════════════════════════════════════════
// The AI draft as a LIVE FEED into the ordinary rapportino (AI report builder MVP, Task 12).
//
// The server's durable draft (one per technician and ticket) is applied into the phone's own Drift
// report REPEATEDLY: after every turn, on resume, on "Aggiorna dalla bozza". Three rules:
//
// 1. Only the confirmed subset is written. A line enters the report when its entry is NOT
//    `NeedsConfirmation` (a plan, an assignment, a checklist question with no answer) and NOT
//    `Ambiguous`/`Conflict` (an open item the technician has to settle) — exactly the set
//    `ConfirmPlanBuilder` writes at Confirm, so the incremental path and Confirm agree. Planned
//    entries stay out and are offered as proposals with an explicit "Accetta" (a property-less
//    confirmed edit); once the server returns them confirmed, the next apply writes them.
//
// 2. Applying is incremental and idempotent, and never overwrites a hand edit. "Hand-edited" is
//    DERIVED, never flagged by the editor: for each line the apply writes, the values it wrote are
//    kept as a per-session baseline (`applied`). A Drift value that differs from its baseline was
//    changed by the technician; a baselined line with no Drift row was removed by hand; a Drift
//    line with no baseline was added by hand. No Drift column or table: the baseline is a small
//    JSON document in SharedPreferences keyed by session id (wiped with every other preference on
//    logout, like the Drift database it describes).
//
// 3. Every hand change goes back to the server as a `ConfirmedEdit` (it then folds as
//    OperatorConfirmed, so a later voice turn that disagrees is flagged, never applied): riding in
//    the next turn's `confirmedEdits`, or as an edits-only request (empty text: no model, no
//    charge) when the technician leaves the editor or taps "Sincronizza modifiche". `synced`
//    records what the server acknowledged so nothing is sent twice; an edits-only batch is
//    persisted with its Idempotency-Key until acknowledged, so a retry (even after a restart)
//    resends the same body under the same key.
//
// Lines are identified the way the server identifies entries: a worker by user id, a material by
// catalogue id or (free text) by its normalised name, a checklist answer by ticket control id.
// Activities have no line in the local report (Confirm derives the title/description from them):
// they are not written here.
//
// Customer sign-off is never written by this path, and nothing here submits or signs.
// ══════════════════════════════════════════════════════════════════════════════

const _uuid = Uuid();
const _emptyGuid = '00000000-0000-0000-0000-000000000000';

/// The marker Confirm writes on a free-text material line; written by the incremental path too so
/// the two paths produce the same row.
const freeTextMaterialNote = 'Da verificare: materiale non trovato a catalogo.';

bool _isRealId(String? id) => id != null && id.isNotEmpty && id != _emptyGuid;

String _normaliseName(String? s) =>
    (s ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

bool _same(Object? a, Object? b) {
  if (a is num && b is num) return a.toDouble() == b.toDouble();
  return a == b;
}

/// The persisted feed of one AI session.
class AiDraftFeedState {
  AiDraftFeedState({
    required this.sessionId,
    this.reportId,
    Map<String, Map<String, Object?>>? applied,
    Map<String, Map<String, Object?>>? synced,
    List<AiEditBatch>? batches,
    this.blocked = false,
    Set<String>? knownControls,
    Map<String, String>? rejected,
    Set<String>? editsOnlyRefused,
    this.applying = false,
  }) : applied = applied ?? {},
       synced = synced ?? {},
       batches = batches ?? [],
       knownControls = knownControls ?? {},
       rejected = rejected ?? {},
       editsOnlyRefused = editsOnlyRefused ?? {};

  final String sessionId;

  /// The local Drift report this session feeds; null until the technician opens the draft in the
  /// editor (accepting a proposal works without one).
  String? reportId;

  /// Per line key: the values the last apply wrote (plus `_id`/`_name` to rebuild an edit).
  final Map<String, Map<String, Object?>> applied;

  /// Per line key: the values the server acknowledged as confirmed edits, `__present` once any
  /// non-removal edit was acknowledged, `__removed` once a removal was.
  final Map<String, Map<String, Object?>> synced;

  /// The edits-only batches not yet acknowledged, in order. ALL of a sync's batches (explicit
  /// actions included) are persisted before the first is sent, so a failure of one never loses a
  /// later one.
  final List<AiEditBatch> batches;

  /// Edits the server refused (400): edit signature -> the server's code. Never sent again; shown
  /// on the editor card. A different value is a different edit and is tried again.
  final Map<String, String> rejected;

  /// Edits the server would not take as an EDITS-ONLY request (422: the request shape, not the
  /// edit, e.g. a server that still requires turn text). Not resent edits-only, but they still
  /// ride in the next voice/typed turn, which is the channel that works.
  final Set<String> editsOnlyRefused;

  /// Set before an apply writes Drift and cleared after its baseline is saved. Found set on load,
  /// the last apply was interrupted in between: its rows have no baseline and must not be mistaken
  /// for hand-added lines.
  bool applying;

  /// The server refused further edit syncs for this session (409 `draft_too_large`).
  bool blocked;

  /// The checklist controls the server draft holds (its ticket's own controls). A Drift answer
  /// for any other control (an asset checklist) is not the draft's business, and the server would
  /// refuse the whole request for it (`edit_reference_not_found`): it is never sent.
  final Set<String> knownControls;

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'reportId': reportId,
    'applied': applied,
    'synced': synced,
    'batches': [for (final b in batches) b.toJson()],
    'blocked': blocked,
    'knownControls': knownControls.toList(),
    'rejected': rejected,
    'editsOnlyRefused': editsOnlyRefused.toList(),
    'applying': applying,
  };

  static Map<String, Map<String, Object?>> _lines(Object? raw) => {
    if (raw is Map)
      for (final e in raw.entries)
        if (e.value is Map) e.key.toString(): Map<String, Object?>.from(e.value as Map),
  };

  factory AiDraftFeedState.fromJson(Map<String, dynamic> json) => AiDraftFeedState(
    sessionId: json['sessionId'] as String? ?? '',
    reportId: json['reportId'] as String?,
    applied: _lines(json['applied']),
    synced: _lines(json['synced']),
    batches: [
      for (final b in (json['batches'] as List<dynamic>? ?? const []))
        if (b is Map<String, dynamic>) AiEditBatch.fromJson(b),
      if (json['batch'] is Map<String, dynamic>)
        AiEditBatch.fromJson(json['batch'] as Map<String, dynamic>),
    ],
    blocked: json['blocked'] == true,
    applying: json['applying'] == true,
    rejected: {
      if (json['rejected'] is Map)
        for (final e in (json['rejected'] as Map).entries) e.key.toString(): e.value.toString(),
    },
    knownControls: {
      for (final k in (json['knownControls'] as List<dynamic>? ?? const [])) k.toString(),
    },
    editsOnlyRefused: {
      for (final k in (json['editsOnlyRefused'] as List<dynamic>? ?? const [])) k.toString(),
    },
  );
}

/// One edits-only request: its key and its body, kept until the server acknowledges it.
class AiEditBatch {
  AiEditBatch({required this.key, required this.edits, required this.derived});

  final String key;
  final List<AiConfirmedEdit> edits;

  /// Parallel to [edits]: true for an edit derived from the report (acknowledged into `synced`),
  /// false for an explicit action (accept a proposal, settle a held removal).
  final List<bool> derived;

  Map<String, dynamic> toJson() => {
    'key': key,
    'edits': [for (final e in edits) e.toJson()],
    'derived': derived,
  };

  factory AiEditBatch.fromJson(Map<String, dynamic> json) {
    final edits = [
      for (final e in (json['edits'] as List<dynamic>? ?? const []))
        if (e is Map<String, dynamic>) AiConfirmedEdit.fromJson(e),
    ];
    final derived = [
      for (final d in (json['derived'] as List<dynamic>? ?? const [])) d == true,
    ];
    return AiEditBatch(
      key: json['key'] as String? ?? _uuid.v4(),
      edits: edits,
      derived: [for (var i = 0; i < edits.length; i++) i < derived.length && derived[i]],
    );
  }
}

/// SharedPreferences-backed state per AI session, plus the report -> session index.
class AiDraftFeedStore {
  AiDraftFeedStore({Future<SharedPreferences> Function()? prefs})
    : _prefs = prefs ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _prefs;

  static String _sessionKey(String sessionId) => 'ai_feed.session.$sessionId';
  static String _reportKey(String reportId) => 'ai_feed.report.$reportId';

  Future<AiDraftFeedState?> load(String sessionId) async {
    final raw = (await _prefs()).getString(_sessionKey(sessionId));
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, dynamic>) return AiDraftFeedState.fromJson(json);
    } catch (_) {
      // An unreadable state is treated as none: the next apply rebuilds the baseline.
    }
    return null;
  }

  Future<void> save(AiDraftFeedState state) async {
    await (await _prefs()).setString(_sessionKey(state.sessionId), jsonEncode(state.toJson()));
  }

  /// The session that feeds [reportId], if any.
  Future<String?> sessionForReport(String reportId) async =>
      (await _prefs()).getString(_reportKey(reportId));

  /// Binds [sessionId] to the local report it feeds (keeping any state it already has).
  Future<void> link({required String sessionId, required String reportId}) async {
    final state = await load(sessionId) ?? AiDraftFeedState(sessionId: sessionId);
    if (state.reportId != null && state.reportId != reportId) {
      // A different report: the old baseline describes rows that are not in it.
      await (await _prefs()).remove(_reportKey(state.reportId!));
      state.applied.clear();
      state.synced.clear();
    }
    state.reportId = reportId;
    await save(state);
    await (await _prefs()).setString(_reportKey(reportId), sessionId);
  }

  /// Forgets the session (Confirm released it, or it was abandoned).
  Future<void> unlink(String sessionId) async {
    final prefs = await _prefs();
    final state = await load(sessionId);
    if (state?.reportId != null) await prefs.remove(_reportKey(state!.reportId!));
    await prefs.remove(_sessionKey(sessionId));
  }
}

// ── per-session serialisation ─────────────────────────────────────────────────

final Map<String, Future<void>> _locks = {};

/// Runs [body] after every earlier locked call for [sessionId]: an apply, a pending-edits read and
/// an acknowledgement read-modify-write the same persisted document.
Future<T> _locked<T>(String sessionId, Future<T> Function() body) {
  final previous = _locks[sessionId] ?? Future<void>.value();
  final done = Completer<void>();
  final mine = done.future;
  _locks[sessionId] = mine;
  return previous.then((_) => body()).whenComplete(() {
    done.complete();
    if (identical(_locks[sessionId], mine)) _locks.remove(sessionId);
  });
}

// ── lines ─────────────────────────────────────────────────────────────────────

enum _Kind { worker, material, control }

/// One report line in the server's identity terms. [values] use the edit property names.
class _Line {
  _Line(this.kind, this.key, {this.id, this.name, required this.values, this.notes});

  final _Kind kind;
  final String key;
  final String? id;
  final String? name;
  final Map<String, Object?> values;
  final String? notes;

  /// Drift row id of the local row this line was read from.
  String? rowId;

  String get editKind => switch (kind) {
    _Kind.worker => AiConfirmedEdit.kindWorker,
    _Kind.material => AiConfirmedEdit.kindMaterial,
    _Kind.control => AiConfirmedEdit.kindControl,
  };
}

String _workerKey(String userId) => 'worker:${userId.toLowerCase()}';
String _controlKey(String id) => 'control:${id.toLowerCase()}';
String? _materialKey(String? id, String? name) {
  if (_isRealId(id)) return 'material:id:${id!.toLowerCase()}';
  final n = _normaliseName(name);
  return n.isEmpty ? null : 'material:name:$n';
}

/// The local line key an edit addresses.
String? lineKeyForEdit(AiConfirmedEdit e) => switch (e.kind) {
  AiConfirmedEdit.kindWorker when _isRealId(e.id) => _workerKey(e.id!),
  AiConfirmedEdit.kindMaterial => _materialKey(e.id, e.name),
  AiConfirmedEdit.kindControl when _isRealId(e.id) => _controlKey(e.id!),
  _ => null,
};

String? _iso(DateTime? d) => d?.toUtc().toIso8601String();

bool _applicable(AiResolutionState s) =>
    s != AiResolutionState.needsConfirmation &&
    s != AiResolutionState.ambiguous &&
    s != AiResolutionState.conflict;

class _DraftLines {
  _DraftLines(this.lines, this.present);
  final List<_Line> lines;

  /// Every key the draft holds in ANY state: an entry that turned into a conflict is still there.
  final Set<String> present;
}

_DraftLines _linesOfDraft(AiCopilotDraftDto d) {
  final lines = <_Line>[];
  final present = <String>{};
  for (final w in d.workers) {
    if (!_isRealId(w.userId)) continue;
    final key = _workerKey(w.userId);
    present.add(key);
    if (!_applicable(w.state)) continue;
    lines.add(
      _Line(
        _Kind.worker,
        key,
        id: w.userId,
        name: w.fullName,
        values: {'hours': w.hours, 'km': w.km ?? 0.0, 'vehicle': w.vehicle},
      ),
    );
  }
  for (final m in d.materials) {
    final id = m.isFreeText ? null : m.materialId;
    final key = _materialKey(id, m.name);
    if (key == null) continue;
    present.add(key);
    // A material with no quantity is not a used material: Confirm does not record it either.
    if (!_applicable(m.state) || m.quantity <= 0) continue;
    final freeText = !_isRealId(id);
    lines.add(
      _Line(
        _Kind.material,
        key,
        id: freeText ? null : id,
        name: m.name,
        values: {'quantity': m.quantity, 'unit': m.unit},
        notes: freeText ? freeTextMaterialNote : null,
      ),
    );
  }
  for (final c in d.controlli) {
    if (!_isRealId(c.ticketControlId)) continue;
    final key = _controlKey(c.ticketControlId);
    present.add(key);
    final hasAnswer =
        c.stringValue != null || c.boolValue != null || c.numberValue != null || c.dateValue != null;
    if (!_applicable(c.state) || !hasAnswer) continue;
    lines.add(
      _Line(
        _Kind.control,
        key,
        id: c.ticketControlId,
        values: {
          'stringValue': c.stringValue,
          'boolValue': c.boolValue,
          'dateValue': _iso(c.dateValue),
          'numberValue': c.numberValue,
        },
      ),
    );
  }
  return _DraftLines(lines, present);
}

List<_Line> _linesOfConfirm(AiConversationConfirmResponse r) => [
  for (final s in r.staff)
    if (_isRealId(s.userId))
      _Line(
        _Kind.worker,
        _workerKey(s.userId),
        id: s.userId,
        values: {'hours': s.hoursWorked, 'km': s.kmTraveled, 'vehicle': s.vehicle},
      ),
  for (final m in r.materials)
    if (_materialKey(m.materialeId, m.freeTextName) case final key?)
      _Line(
        _Kind.material,
        key,
        id: _isRealId(m.materialeId) ? m.materialeId : null,
        name: m.freeTextName,
        values: {'quantity': m.quantity, 'unit': m.unitOfMeasure},
        notes: m.notes,
      ),
  for (final c in r.controlli)
    if (_isRealId(c.ticketControlId))
      _Line(
        _Kind.control,
        _controlKey(c.ticketControlId),
        id: c.ticketControlId,
        values: {
          'stringValue': c.stringValue,
          'boolValue': c.boolValue,
          'dateValue': _iso(c.dateValue),
          'numberValue': c.numberValue,
        },
      ),
];

/// Applies the server draft into the linked report and derives the technician's hand edits.
class AiDraftFeed {
  AiDraftFeed({required AppDatabase db, required AiDraftFeedStore store})
    : _db = db,
      _store = store;

  final AppDatabase _db;
  final AiDraftFeedStore _store;

  AiDraftFeedStore get store => _store;

  /// Writes the confirmed subset of [draft] into the report linked to [sessionId]. Returns false
  /// (and writes nothing) when the session feeds no report.
  Future<bool> apply(String sessionId, AiCopilotDraftDto draft) => _locked(sessionId, () async {
    final state = await _store.load(sessionId);
    final reportId = state?.reportId;
    if (state == null || reportId == null) return false;
    await _guardWritable(state, reportId);
    final lines = _linesOfDraft(draft);
    state.knownControls
      ..clear()
      ..addAll(lines.present.where((k) => k.startsWith('control:')));
    await _marked(state, (recovering) async {
      await _applyLines(
        state,
        reportId,
        lines.lines,
        present: lines.present,
        recovering: recovering,
      );
      // Instruments stay out of the line diff: their only hand-editable columns are the two notes
      // and the expiry acknowledgement, which belong to the Strumenti step — the copilot fills
      // them and never corrects them. The write is idempotent by row id, so a turn that says the
      // same thing twice costs nothing.
      await writeAiStrumenti(
        DraftReportRepository(_db),
        reportId: reportId,
        lines: AiStrumentoLine.fromDraft(draft),
      );
    });
    return true;
  });

  /// Runs [write] between the persisted "apply in progress" marker and the baseline save.
  /// [write] receives whether an earlier apply was interrupted (see [AiDraftFeedState.applying]).
  ///
  /// A write that THROWS rolled its Drift transaction back, so nothing is half-written, and the
  /// in-memory baseline [write] mutated inside that transaction describes rows that never landed:
  /// the STORED baseline is restored from a snapshot taken before the write, so the next derive
  /// never reads those keys as removed by hand. The crash marker is cleared only after that
  /// restore (and only if it was not already set by an earlier, killed apply). Only a killed
  /// process leaves it set.
  Future<void> _marked(AiDraftFeedState state, Future<void> Function(bool recovering) write) async {
    final recovering = state.applying;
    final snapshot = jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>;
    state.applying = true;
    await _store.save(state);
    try {
      await write(recovering);
    } catch (_) {
      final restored = AiDraftFeedState.fromJson(snapshot)..applying = recovering;
      await _store.save(restored);
      rethrow;
    }
    state.applying = false;
    await _store.save(state);
  }

  /// The one guard every AI writer goes through: the linked report must still be the
  /// technician's editable draft. A signed, queued, failed-in-queue or sent report is never
  /// touched (the queue reads its lines from Drift at send time): [AiFeedReportLockedException]
  /// says why. The session stays LINKED to that report: the link is the only durable record that
  /// this server session was already used, so every later entry (copilot resume, Compila,
  /// Conferma, a leave-sync) re-detects it. It is dropped only by a confirmed release/abandon.
  /// The AI draft itself stays readable in the copilot.
  Future<void> _guardWritable(AiDraftFeedState state, String reportId) async {
    final header = await (_db.select(
      _db.draftReports,
    )..where((t) => t.id.equals(reportId))).getSingleOrNull();
    final refusal = feedWriteRefusal(header);
    if (refusal == null) return;
    throw AiFeedReportLockedException(refusal);
  }

  /// Whether [reportId] was handed to the submission queue or sent (not merely signed): the AI
  /// draft behind it has then been used.
  Future<bool> reportWasSubmitted(String reportId) async {
    final r = await (_db.select(_db.draftReports)..where((t) => t.id.equals(reportId)))
        .getSingleOrNull();
    if (r == null) return false;
    return r.stato != 'Bozza' ||
        DraftSubmissionState.fromString(r.submissionState) != DraftSubmissionState.draft;
  }

  /// Whether [reportId] may still be written by the AI feed (see [feedWriteRefusal]).
  Future<String?> writeRefusalFor(String reportId) async => feedWriteRefusal(
    await (_db.select(_db.draftReports)..where((t) => t.id.equals(reportId))).getSingleOrNull(),
  );

  /// The end-of-flow Confirm response, applied into the SAME report the incremental path fed:
  /// matched by identity, so nothing is duplicated, and hand edits still win. Header text is only
  /// filled where the technician left it empty. Returns false when no report is linked.
  Future<bool> applyConfirmResponse(String sessionId, AiConversationConfirmResponse r) =>
      _locked(sessionId, () async {
        final state = await _store.load(sessionId);
        final reportId = state?.reportId;
        if (state == null || reportId == null) return false;
        await _guardWritable(state, reportId);
        // No `present` set: Confirm leaves out conflicts and plans, so absence proves nothing here.
        await _marked(state, (recovering) async {
          await _applyLines(
            state,
            reportId,
            _linesOfConfirm(r),
            present: null,
            recovering: recovering,
          );
          // The resolved instruments, with the server's calibration verdict for the job's date.
          // A line the server could not settle (expired, not acknowledged) lands as-is: the
          // Strumenti step asks the technician to confirm it, and the submit is refused until then.
          await writeAiStrumenti(
            DraftReportRepository(_db),
            reportId: reportId,
            lines: r.strumenti.map(AiStrumentoLine.fromResolved),
          );
        });
        final header = await (_db.select(
          _db.draftReports,
        )..where((t) => t.id.equals(reportId))).getSingleOrNull();
        if (header != null) {
          final hasMaterials = (await _rows(reportId)).any((l) => l.kind == _Kind.material);
          await (_db.update(_db.draftReports)..where((t) => t.id.equals(reportId))).write(
            DraftReportsCompanion(
              title: header.title.trim().isEmpty && r.title.trim().isNotEmpty
                  ? Value(r.title)
                  : const Value.absent(),
              details: (header.details ?? '').trim().isEmpty && (r.details ?? '').isNotEmpty
                  ? Value(r.details)
                  : const Value.absent(),
              materialiNotRequired: r.materialiNotRequired && !hasMaterials
                  ? const Value(true)
                  : const Value.absent(),
              isAiAssisted: const Value(true),
              updatedAt: Value(DateTime.now().toUtc()),
            ),
          );
        }
        await _store.save(state);
        return true;
      });

  /// Every hand change since the last acknowledgement, as confirmed edits.
  Future<List<AiConfirmedEdit>> pendingEdits(String sessionId) => _locked(sessionId, () async {
    final state = await _store.load(sessionId);
    if (state == null || state.reportId == null) return const <AiConfirmedEdit>[];
    return _pending(state);
  });

  /// What the editor card shows persistently: whether syncing is blocked, and the hand edits that
  /// cannot reach the server (with why).
  Future<AiFeedStatus> status(String sessionId) => _locked(sessionId, () async {
    final state = await _store.load(sessionId);
    if (state == null) return const AiFeedStatus();
    final unsendable = state.reportId == null || state.applying
        ? const <String>[]
        : [for (final u in (await _derive(state)).unsendable) describeUnsendable(u.$1, u.$2)];
    return AiFeedStatus(blocked: state.blocked, unsendable: unsendable);
  });

  /// Records [edits] as acknowledged by the server (derived edits only).
  Future<void> acknowledge(String sessionId, List<AiConfirmedEdit> edits) =>
      _locked(sessionId, () async {
        final state = await _store.load(sessionId);
        if (state == null) return;
        acknowledgeInto(state, edits);
        await _store.save(state);
      });

  /// Drops a line from the baseline and the acknowledgements, so the next apply re-inserts it
  /// (a held removal the technician chose to bring back).
  Future<void> forgetLine(String sessionId, String lineKey) => _locked(sessionId, () async {
    final state = await _store.load(sessionId);
    if (state == null) return;
    state.applied.remove(lineKey);
    state.synced.remove(lineKey);
    await _store.save(state);
  });

  // ── internals (callers hold the session lock) ──────────────────────────────

  static void acknowledgeInto(AiDraftFeedState state, Iterable<AiConfirmedEdit> edits) {
    for (final e in edits) {
      final key = lineKeyForEdit(e);
      if (key == null) continue;
      final s = state.synced.putIfAbsent(key, () => <String, Object?>{});
      if (e.id != null) s['_id'] = e.id;
      if (e.name != null) s['_name'] = e.name;
      if (e.remove) {
        s.removeWhere((k, _) => !k.startsWith('_'));
        s['__removed'] = true;
      } else {
        s.remove('__removed');
        s['__present'] = true;
        if (e.property != null) s[e.property!] = e.value;
      }
    }
  }

  Future<List<_Line>> _rows(String reportId) async {
    final out = <_Line>[];
    final staff = await (_db.select(
      _db.reportStaffTable,
    )..where((t) => t.reportId.equals(reportId))).get();
    for (final s in staff) {
      if (s.userId.isEmpty) continue;
      out.add(
        _Line(
            _Kind.worker,
            _workerKey(s.userId),
            id: s.userId,
            values: {'hours': s.hoursWorked, 'km': s.kmTraveled, 'vehicle': s.vehicle},
          )
          ..rowId = s.id,
      );
    }
    final materials = await (_db.select(
      _db.reportMateriali,
    )..where((t) => t.reportId.equals(reportId))).get();
    for (final m in materials) {
      final key = _materialKey(m.materialeId, m.freeTextName);
      if (key == null) continue;
      out.add(
        _Line(
            _Kind.material,
            key,
            id: _isRealId(m.materialeId) ? m.materialeId : null,
            name: m.freeTextName,
            values: {'quantity': m.quantity, 'unit': m.unitOfMeasure},
          )
          ..rowId = m.id,
      );
    }
    final controls = await (_db.select(
      _db.reportControlli,
    )..where((t) => t.reportId.equals(reportId))).get();
    for (final c in controls) {
      out.add(
        _Line(
            _Kind.control,
            _controlKey(c.controlId),
            id: c.controlId,
            values: {
              'stringValue': c.stringValue,
              'boolValue': c.boolValue,
              'dateValue': _iso(c.dateValue),
              'numberValue': c.numberValue,
            },
          )
          ..rowId = c.id,
      );
    }
    return out;
  }

  Map<String, _Line> _byKey(List<_Line> lines) {
    final map = <String, _Line>{};
    for (final l in lines) {
      map.putIfAbsent(l.key, () => l);
    }
    return map;
  }

  Future<void> _applyLines(
    AiDraftFeedState state,
    String reportId,
    List<_Line> incoming, {
    required Set<String>? present,
    bool recovering = false,
  }) async {
    final header = await (_db.select(
      _db.draftReports,
    )..where((t) => t.id.equals(reportId))).getSingleOrNull();
    if (header == null) return;
    final rows = _byKey(await _rows(reportId));
    final now = DateTime.now().toUtc();
    var changed = false;

    await _db.transaction(() async {
      final seen = <String>{};
      for (final line in incoming) {
        if (!seen.add(line.key)) continue; // the first entry wins, as at Confirm
        final row = rows[line.key];
        final base = state.applied[line.key];
        if (base != null) {
          if (row == null) continue; // removed by hand: never re-added by an apply
          final updates = <String, Object?>{};
          for (final p in line.values.keys) {
            final local = row.values[p];
            if (_same(local, base[p])) {
              if (!_same(line.values[p], local)) updates[p] = line.values[p];
              base[p] = line.values[p];
            } else if (_same(line.values[p], local)) {
              base[p] = line.values[p]; // the server caught up with the hand edit
            }
            // else: hand-edited, and the server says otherwise — the technician's value stays.
          }
          if (updates.isNotEmpty) {
            await _update(row, updates, now);
            changed = true;
          }
          continue;
        }
        if (row != null) {
          // A line added by hand (the Ore tile's own row for the technician, say) that the server
          // now holds too. It gets a baseline here: what the technician left empty (or at the
          // editor's default) takes the server value; what they typed stays, and differs from the
          // baseline, so it is a hand edit and goes to the server as confirmed.
          final adopted = <String, Object?>{'_id': ?line.id, '_name': ?line.name};
          final updates = <String, Object?>{};
          for (final p in line.values.keys) {
            final local = row.values[p];
            final server = line.values[p];
            if (recovering && _same(local, server)) {
              adopted[p] = local; // written by the interrupted apply itself
            } else if (_isEditorDefault(p, local)) {
              if (!_isEditorDefault(p, server) && !_same(server, local)) updates[p] = server;
              adopted[p] = _isEditorDefault(p, server) ? local : server;
            } else {
              adopted[p] = server;
            }
          }
          if (updates.isNotEmpty) {
            await _update(row, updates, now);
            changed = true;
          }
          state.applied[line.key] = adopted;
          continue;
        }
        // Removed by hand after the technician added it: theirs, not re-added.
        if (state.synced.containsKey(line.key)) continue;
        await _insert(line, reportId, header.tenantId, now);
        state.applied[line.key] = {
          ...line.values,
          '_id': ?line.id,
          '_name': ?line.name,
        };
        changed = true;
      }

      // An entry the server no longer has at all (removed by voice, or re-identified) leaves the
      // report too — unless the technician changed the line, which makes it theirs.
      if (present != null) {
        for (final key in state.applied.keys.toList()) {
          if (present.contains(key)) continue;
          final row = rows[key];
          final base = state.applied[key]!;
          if (row == null) {
            state.applied.remove(key);
            continue;
          }
          final untouched = row.values.keys.every((p) => _same(row.values[p], base[p]));
          if (untouched) {
            await _delete(row);
            state.applied.remove(key);
            changed = true;
          }
        }
      }

      if (changed) {
        // Provenance only. Sign-off, signatures and the submission state are never touched.
        await (_db.update(_db.draftReports)..where((t) => t.id.equals(reportId))).write(
          DraftReportsCompanion(isAiAssisted: const Value(true), updatedAt: Value(now)),
        );
      }
    });
  }

  Future<void> _insert(_Line l, String reportId, String tenantId, DateTime now) async {
    final v = l.values;
    switch (l.kind) {
      case _Kind.worker:
        await _db
            .into(_db.reportStaffTable)
            .insert(
              ReportStaffTableCompanion.insert(
                id: _uuid.v4(),
                tenantId: tenantId,
                createdAt: now,
                reportId: reportId,
                userId: l.id!,
                hoursWorked: Value((v['hours'] as num?)?.toDouble()),
                kmTraveled: Value((v['km'] as num?)?.toDouble() ?? 0),
                vehicle: Value(v['vehicle'] as String?),
              ),
            );
      case _Kind.material:
        await _db
            .into(_db.reportMateriali)
            .insert(
              ReportMaterialiCompanion.insert(
                id: _uuid.v4(),
                tenantId: tenantId,
                createdAt: now,
                reportId: reportId,
                materialeId: Value(l.id),
                freeTextName: Value(l.id == null ? l.name?.trim() : null),
                quantity: (v['quantity'] as num).toDouble(),
                unitOfMeasure: Value(v['unit'] as String?),
                notes: Value(l.notes),
                // No magazzino: guessing one would move stock nobody asked for.
              ),
            );
      case _Kind.control:
        await _db
            .into(_db.reportControlli)
            .insertOnConflictUpdate(
              ReportControlliCompanion.insert(
                // The Controlli step's own row id, so its next edit updates this row.
                id: controlRowId(reportId, l.id!),
                tenantId: tenantId,
                createdAt: now,
                reportId: reportId,
                controlId: l.id!,
                stringValue: Value(v['stringValue'] as String?),
                boolValue: Value(v['boolValue'] as bool?),
                dateValue: Value(_parseDate(v['dateValue'])),
                numberValue: Value((v['numberValue'] as num?)?.toDouble()),
              ),
            );
    }
  }

  static DateTime? _parseDate(Object? v) => v is String ? DateTime.tryParse(v) : null;

  Future<void> _update(_Line row, Map<String, Object?> u, DateTime now) async {
    final id = row.rowId!;
    switch (row.kind) {
      case _Kind.worker:
        await (_db.update(_db.reportStaffTable)..where((t) => t.id.equals(id))).write(
          ReportStaffTableCompanion(
            hoursWorked: u.containsKey('hours')
                ? Value((u['hours'] as num?)?.toDouble())
                : const Value.absent(),
            kmTraveled: u.containsKey('km')
                ? Value((u['km'] as num?)?.toDouble() ?? 0)
                : const Value.absent(),
            vehicle: u.containsKey('vehicle') ? Value(u['vehicle'] as String?) : const Value.absent(),
            updatedAt: Value(now),
          ),
        );
      case _Kind.material:
        await (_db.update(_db.reportMateriali)..where((t) => t.id.equals(id))).write(
          ReportMaterialiCompanion(
            quantity: u['quantity'] is num
                ? Value((u['quantity'] as num).toDouble())
                : const Value.absent(),
            unitOfMeasure: u.containsKey('unit') ? Value(u['unit'] as String?) : const Value.absent(),
            updatedAt: Value(now),
          ),
        );
      case _Kind.control:
        await (_db.update(_db.reportControlli)..where((t) => t.id.equals(id))).write(
          ReportControlliCompanion(
            stringValue: u.containsKey('stringValue')
                ? Value(u['stringValue'] as String?)
                : const Value.absent(),
            boolValue: u.containsKey('boolValue')
                ? Value(u['boolValue'] as bool?)
                : const Value.absent(),
            dateValue: u.containsKey('dateValue')
                ? Value(_parseDate(u['dateValue']))
                : const Value.absent(),
            numberValue: u.containsKey('numberValue')
                ? Value((u['numberValue'] as num?)?.toDouble())
                : const Value.absent(),
            updatedAt: Value(now),
          ),
        );
    }
  }

  Future<void> _delete(_Line row) async {
    final id = row.rowId!;
    switch (row.kind) {
      case _Kind.worker:
        await (_db.delete(_db.reportStaffTable)..where((t) => t.id.equals(id))).go();
      case _Kind.material:
        await (_db.delete(_db.reportMateriali)..where((t) => t.id.equals(id))).go();
      case _Kind.control:
        await (_db.delete(_db.reportControlli)..where((t) => t.id.equals(id))).go();
    }
  }

  /// A value worth confirming on a line the technician added: km 0 and an empty vehicle are the
  /// editor's defaults, not something the technician stated.
  static bool _meaningful(String property, Object? v) {
    if (v == null) return false;
    if (property == 'km' && v is num && v == 0) return false;
    if (v is String && v.trim().isEmpty) return false;
    return true;
  }

  /// Value empty, or the editor's own default for it (km 0): nothing the technician stated.
  static bool _isEditorDefault(String property, Object? v) {
    if (v == null) return true;
    if (property == 'km' && v is num && v == 0) return true;
    return v is String && v.trim().isEmpty;
  }

  Future<List<AiConfirmedEdit>> _pending(AiDraftFeedState state, {bool forTurn = false}) async =>
      (await _derive(state, forTurn: forTurn)).sendable;

  /// The hand edits split into those that can be sent and those that cannot (refused by the
  /// client-side mirror of `ConfirmedEditValidator`, or refused earlier by the server).
  Future<({List<AiConfirmedEdit> sendable, List<(AiConfirmedEdit, String)> unsendable})> _derive(
    AiDraftFeedState state, {
    bool forTurn = false,
  }) async {
    final sendable = <AiConfirmedEdit>[];
    final unsendable = <(AiConfirmedEdit, String)>[];
    // An interrupted apply leaves rows with no baseline: derive nothing until it is recovered.
    if (state.applying) return (sendable: sendable, unsendable: unsendable);
    for (final e in await _allEdits(state)) {
      final local = invalidEditReason(e);
      final server = state.rejected[editSignature(e)];
      if (local != null) {
        unsendable.add((e, local));
      } else if (server != null) {
        unsendable.add((e, serverRejectionReason(server)));
      } else if (forTurn || !state.editsOnlyRefused.contains(editSignature(e))) {
        sendable.add(e);
      }
    }
    return (sendable: sendable, unsendable: unsendable);
  }

  Future<List<AiConfirmedEdit>> _allEdits(AiDraftFeedState state) async {
    final rows = _byKey(await _rows(state.reportId!));
    final edits = <AiConfirmedEdit>[];

    AiConfirmedEdit edit(_Line l, {String? property, Object? value, bool remove = false}) =>
        AiConfirmedEdit(
          kind: l.editKind,
          id: l.id,
          // A free-text material is identified by its name; an id-keyed entry needs none.
          name: l.id == null ? l.name?.trim() : null,
          property: property,
          value: value,
          remove: remove,
        );

    for (final row in rows.values) {
      final s = state.synced[row.key] ?? const <String, Object?>{};
      final base = state.applied[row.key];
      final reAdded = s['__removed'] == true;
      if (row.kind == _Kind.control && base == null && !state.knownControls.contains(row.key)) {
        continue;
      }
      if (base != null && !reAdded) {
        for (final p in row.values.keys) {
          final v = row.values[p];
          if (v == null || _same(v, base[p]) || (s.containsKey(p) && _same(s[p], v))) continue;
          edits.add(edit(row, property: p, value: v));
        }
        continue;
      }
      // Added by hand (or brought back after a removal): the entry itself, then its values.
      if (row.kind != _Kind.control && (s['__present'] != true || reAdded)) edits.add(edit(row));
      for (final p in row.values.keys) {
        final v = row.values[p];
        if (!_meaningful(p, v) || (s.containsKey(p) && _same(s[p], v))) continue;
        edits.add(edit(row, property: p, value: v));
      }
    }

    // Removed by hand: a baselined line, or a hand line the server already knows.
    for (final entry in state.applied.entries) {
      if (rows.containsKey(entry.key)) continue;
      if (state.synced[entry.key]?['__removed'] == true) continue;
      final r = _removal(entry.key, entry.value);
      if (r != null) edits.add(r);
    }
    for (final entry in state.synced.entries) {
      if (rows.containsKey(entry.key) || state.applied.containsKey(entry.key)) continue;
      if (entry.value['__present'] != true || entry.value['__removed'] == true) continue;
      final r = _removal(entry.key, entry.value);
      if (r != null) edits.add(r);
    }
    return edits;
  }

  static AiConfirmedEdit? _removal(String key, Map<String, Object?> meta) {
    final id = meta['_id'] as String?;
    final name = meta['_name'] as String?;
    if (key.startsWith('worker:')) {
      return _isRealId(id) ? AiConfirmedEdit(kind: 'worker', id: id, remove: true) : null;
    }
    if (key.startsWith('control:')) {
      return _isRealId(id) ? AiConfirmedEdit(kind: 'control', id: id, remove: true) : null;
    }
    if (key.startsWith('material:id:')) {
      return AiConfirmedEdit(kind: 'material', id: id ?? key.substring(12), remove: true);
    }
    if (key.startsWith('material:name:')) {
      return AiConfirmedEdit(kind: 'material', name: name ?? key.substring(14), remove: true);
    }
    return null;
  }
}

/// What the editor card shows about the feed, persistently.
class AiFeedStatus {
  const AiFeedStatus({this.blocked = false, this.unsendable = const []});

  /// The server refuses further edit syncs for this draft.
  final bool blocked;

  /// One Italian line per hand edit that cannot reach the server, naming it and why.
  final List<String> unsendable;

  String get blockedMessage => _blockedMessage;

  String get notice => unsendable.isEmpty
      ? ''
      : '${unsendable.length} ${unsendable.length == 1 ? 'modifica non sincronizzabile' : 'modifiche non sincronizzabili'}: '
            '${unsendable.join('; ')}. Correggile nel rapporto di intervento.';
}

/// A stable identity for an edit (what the server refused is never sent again).
String editSignature(AiConfirmedEdit e) => jsonEncode(e.toJson());

final _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// The client-side mirror of the server's `ConfirmedEditValidator` (strings at most 500
/// characters, an identifying name with a letter or digit, numbers finite and not negative, a
/// parsable date): an edit it refuses would make the server refuse the whole request, so it is
/// never sent. Returns the Italian reason, or null when the edit is fine.
String? invalidEditReason(AiConfirmedEdit e) {
  const max = 500;
  if (e.id == _emptyGuid) return 'identificativo mancante';
  final name = e.name;
  if (name != null && name.length > max) return 'nome oltre $max caratteri';
  final nameIdentifies =
      e.kind == AiConfirmedEdit.kindActivity || (e.kind == AiConfirmedEdit.kindMaterial && e.id == null);
  if (nameIdentifies && !_letterOrDigit.hasMatch(name ?? '')) return 'nome senza lettere o cifre';
  final v = e.value;
  if (v is num && (v.isNaN || v.isInfinite)) return 'numero non valido';
  if (v is num && v < 0) return 'valore negativo';
  if (v is String && v.length > max) return 'testo oltre $max caratteri';
  if (e.property == 'dateValue' && (v is! String || DateTime.tryParse(v) == null)) {
    return 'data non valida';
  }
  return null;
}

/// The server's 400 code, in words.
String serverRejectionReason(String code) => switch (code) {
  'edit_reference_not_found' => 'non esiste più o non appartiene al ticket',
  'edit_value_invalid' => 'valore non accettato dal server',
  'edit_property_unknown' => 'campo non accettato dal server',
  _ => 'rifiutata dal server',
};

/// "materiale «--» (quantità): nome senza lettere o cifre".
String describeUnsendable(AiConfirmedEdit e, String reason) {
  final what = switch (e.kind) {
    AiConfirmedEdit.kindWorker => 'tecnico',
    AiConfirmedEdit.kindMaterial => 'materiale',
    AiConfirmedEdit.kindControl => 'risposta della checklist',
    AiConfirmedEdit.kindActivity => 'attività',
    _ => 'voce',
  };
  final label = e.name != null && e.name!.isNotEmpty ? ' «${e.name}»' : '';
  final field = switch (e.property) {
    'hours' => ' (ore)',
    'km' => ' (km)',
    'vehicle' => ' (veicolo)',
    'quantity' => ' (quantità)',
    'unit' => ' (unità)',
    null => e.remove ? ' (rimozione)' : '',
    _ => ' (risposta)',
  };
  return '$what$label$field: $reason';
}

/// Null when [r] may still be written by an AI path; otherwise the Italian reason it may not.
/// Editable means: a Bozza, never handed to the submission queue (`draft`: not ready, uploading,
/// submitting, submitted or failed-in-queue), and not signed by the customer.
String? feedWriteRefusal(DraftReport? r) {
  if (r == null) return 'Il rapporto di intervento collegato non è più su questo telefono.';
  final submission = DraftSubmissionState.fromString(r.submissionState);
  if (r.stato != 'Bozza' || submission != DraftSubmissionState.draft) {
    return 'Il rapporto di intervento collegato è già stato inviato o è in coda di invio: '
        'la bozza AI non lo modifica più.';
  }
  if (r.customerSignatureAllegatoId != null) {
    return 'Il rapporto di intervento collegato è già firmato dal cliente: '
        'la bozza AI non lo modifica più.';
  }
  return null;
}

/// The linked report may no longer be written by the AI (see [feedWriteRefusal]); the session
/// stays linked to it as the record that it was used.
class AiFeedReportLockedException implements Exception {
  const AiFeedReportLockedException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The server no longer has the AI session (404): the feed was released.
class AiFeedSessionGoneException implements Exception {
  const AiFeedSessionGoneException();
  String get message =>
      'La bozza AI non esiste più sul server (scaduta o chiusa): le modifiche restano nel '
      'rapporto di intervento, ma non arrivano più all\'AI.';
  @override
  String toString() => message;
}

/// Releases the AI session behind [reportId] once that report was submitted on this device, so
/// a later visit to the same ticket can never re-apply this visit's lines into a new report.
/// Best effort: the feed is unlinked only once the server confirmed the release; otherwise the
/// copilot's resume check still sees the link to a sent report and asks the technician.
Future<void> releaseAiSessionForSubmittedReport({
  required AiDraftFeedStore store,
  required AiApiClient client,
  required String reportId,
}) async {
  final sessionId = await store.sessionForReport(reportId);
  if (sessionId == null) return;
  if (await client.tryAbandonConversation(sessionId)) await store.unlink(sessionId);
}

/// The server refuses further edit syncs for this draft; retrying cannot help.
class AiEditSyncBlockedException implements Exception {
  const AiEditSyncBlockedException(this.message);
  final String message;
  @override
  String toString() => message;
}

const _blockedMessage =
    'La bozza AI ha raggiunto il limite di modifiche sincronizzabili: le tue modifiche restano nel '
    'rapporto di intervento, ma l\'AI non le vedrà più.';

/// Delivers hand edits to the server: in a turn's `confirmedEdits`, or as edits-only batches of
/// at most [AiConfirmedEdit.maxPerRequest], each persisted with its Idempotency-Key until
/// acknowledged.
class AiEditSyncer {
  AiEditSyncer({
    required AiApiClient client,
    required AiDraftFeed feed,
    required AiDraftFeedStore store,
    this.retryDelay = const Duration(seconds: 2),
    String Function()? newKey,
  }) : _client = client,
       _feed = feed,
       _store = store,
       _newKey = newKey ?? _uuid.v4;

  final AiApiClient _client;
  final AiDraftFeed _feed;
  final AiDraftFeedStore _store;
  final Duration retryDelay;
  final String Function() _newKey;

  static const _maxInProgressRetries = 5;

  /// "Accetta" on a planned/assigned worker: accepted as shown.
  static AiConfirmedEdit acceptWorker(AiDraftWorkerRef w) =>
      AiConfirmedEdit(kind: AiConfirmedEdit.kindWorker, id: w.userId);

  /// "Accetta" on a planned material: accepted as shown (its planned quantity and unit included).
  static AiConfirmedEdit acceptMaterial(AiDraftMaterialUsage m) =>
      _isRealId(m.materialId) && !m.isFreeText
      ? AiConfirmedEdit(kind: AiConfirmedEdit.kindMaterial, id: m.materialId)
      : AiConfirmedEdit(kind: AiConfirmedEdit.kindMaterial, name: m.name);

  /// The edit that settles a held removal (`removed.<collection>.<id:…|name:…>`): [reAdd] brings
  /// the entry back by hand (by id and name), otherwise the removal is confirmed again. Null when
  /// the entry cannot be re-added without a value (a checklist answer, a worker known by name only).
  static AiConfirmedEdit? heldRemovalEdit(AiCandidateFact fact, {required bool reAdd}) {
    if (!fact.isHeldRemoval) return null;
    final collection = fact.removedCollection;
    if (collection == null) return null;
    final key = fact.field.substring('removed.'.length + collection.length + 1);
    final kind = switch (collection) {
      'workers' => AiConfirmedEdit.kindWorker,
      'materials' => AiConfirmedEdit.kindMaterial,
      'activities' => AiConfirmedEdit.kindActivity,
      'controlli' => AiConfirmedEdit.kindControl,
      _ => null,
    };
    if (kind == null) return null;
    final id = key.startsWith('id:') ? key.substring(3) : null;
    final keyName = key.startsWith('name:') ? key.substring(5) : null;
    final label = fact.conflictOperatorValue ?? keyName;
    if (!reAdd) {
      if (id == null && keyName == null) return null;
      return AiConfirmedEdit(kind: kind, id: id, name: id == null ? keyName : null, remove: true);
    }
    if (kind == AiConfirmedEdit.kindControl) return null;
    if (kind == AiConfirmedEdit.kindWorker && id == null) return null;
    if (id == null && (label == null || label.trim().isEmpty)) return null;
    return AiConfirmedEdit(kind: kind, id: id, name: label);
  }

  /// Sends every pending hand edit, plus [extra] explicit actions, as edits-only batches. Returns
  /// the draft of the last acknowledged batch, or null when nothing was sent. Throws
  /// [AiEditSyncBlockedException] whenever the server refuses more syncs for this draft (every
  /// call, so the technician is told each time, never "nothing to sync"). A 400 isolates the
  /// refused edit by halving the batch: only that edit is dropped, recorded as unsendable and
  /// shown on the card; the rest still go. Any other failure leaves the queue persisted.
  Future<AiCopilotDraftDto?> sync(
    String sessionId, {
    List<AiConfirmedEdit> extra = const [],
  }) => _locked(sessionId, () => _sync(sessionId, extra));

  /// The edits to ride in the next turn of [sessionId] (at most one request's worth). A queued
  /// batch, or more pending edits than one request holds, is flushed edits-only first. Never
  /// throws: if the flush fails the turn still goes, without edits.
  Future<List<AiConfirmedEdit>> editsForTurn(String sessionId) => _locked(sessionId, () async {
    final state = await _store.load(sessionId);
    if (state == null || state.blocked || state.reportId == null) {
      return const <AiConfirmedEdit>[];
    }
    // A queued batch is flushed first; whether that works or not, the derivable edits still
    // ride in the turn (idempotent under the turn's own key): a stuck queue never silences them.
    if (state.batches.isNotEmpty) {
      try {
        await _sync(sessionId, const []);
      } catch (_) {}
    }
    final fresh = await _store.load(sessionId);
    if (fresh == null || fresh.blocked || fresh.reportId == null) {
      return const <AiConfirmedEdit>[];
    }
    var pending = await _feed._pending(fresh, forTurn: true);
    if (pending.length > AiConfirmedEdit.maxPerRequest) {
      try {
        await _sync(sessionId, const []);
      } catch (_) {}
      final after = await _store.load(sessionId);
      if (after == null || after.reportId == null) return const <AiConfirmedEdit>[];
      pending = await _feed._pending(after, forTurn: true);
    }
    return pending.take(AiConfirmedEdit.maxPerRequest).toList();
  });

  /// A turn carrying [edits] was refused (400/422) and is being resent without them: whatever of
  /// [edits] is still unacknowledged is refused for good (shown on the card), so it can never
  /// silence another turn. A changed value is a new edit and is tried again.
  Future<void> refuseTurnEdits(String sessionId, List<AiConfirmedEdit> edits, String code) =>
      _locked(sessionId, () async {
        final state = await _store.load(sessionId);
        if (state == null || state.reportId == null) return;
        final still = {
          for (final e in await _feed._pending(state, forTurn: true)) editSignature(e),
        };
        for (final e in edits) {
          final sig = editSignature(e);
          if (still.contains(sig)) state.rejected[sig] = code;
        }
        await _store.save(state);
      });

  /// The turn that carried [edits] was accepted.
  Future<void> acknowledge(String sessionId, List<AiConfirmedEdit> edits) =>
      _feed.acknowledge(sessionId, edits);

  /// "Reinserisci" ([reAdd]) or "Mantieni rimosso" on a held removal. Returns the server's draft.
  Future<AiCopilotDraftDto?> resolveHeldRemoval(
    String sessionId,
    AiCandidateFact fact, {
    required bool reAdd,
  }) async {
    final edit = heldRemovalEdit(fact, reAdd: reAdd);
    if (edit == null) throw ArgumentError.value(fact.field, 'fact', 'cannot be resolved so');
    final draft = await sync(sessionId, extra: [edit]);
    if (reAdd) {
      final key = lineKeyForEdit(edit);
      if (key != null) await _feed.forgetLine(sessionId, key);
    }
    return draft;
  }

  List<AiEditBatch> _chunk(List<AiConfirmedEdit> edits, {required bool derived}) => [
    for (var i = 0; i < edits.length; i += AiConfirmedEdit.maxPerRequest)
      AiEditBatch(
        key: _newKey(),
        edits: edits.sublist(i, (i + AiConfirmedEdit.maxPerRequest).clamp(0, edits.length)),
        derived: List.filled(
          (i + AiConfirmedEdit.maxPerRequest).clamp(0, edits.length) - i,
          derived,
        ),
      ),
  ];

  Future<AiCopilotDraftDto?> _sync(String sessionId, List<AiConfirmedEdit> extra) async {
    final state = await _store.load(sessionId) ?? AiDraftFeedState(sessionId: sessionId);
    if (state.blocked) {
      state.batches.clear();
      await _store.save(state);
      throw const AiEditSyncBlockedException(_blockedMessage);
    }
    // Explicit actions are queued (and persisted) before anything already queued is sent.
    final invalidExtra = [for (final e in extra) if (invalidEditReason(e) != null) e];
    if (invalidExtra.isNotEmpty) {
      throw AiConversationException(400, invalidEditReason(invalidExtra.first)!);
    }
    if (extra.isNotEmpty) {
      state.batches.addAll(_chunk(extra, derived: false));
      await _store.save(state);
    }
    var last = await _drain(state);

    if (state.reportId != null) {
      final derived = await _feed._pending(state);
      if (derived.isNotEmpty) {
        state.batches.addAll(_chunk(derived, derived: true));
        await _store.save(state);
        last = await _drain(state) ?? last;
      }
    }
    return last;
  }

  /// Sends the queue front to back; each batch leaves it only once acknowledged (or, refused, once
  /// isolated down to the single refused edit).
  Future<AiCopilotDraftDto?> _drain(AiDraftFeedState state) async {
    AiCopilotDraftDto? last;
    AiConversationException? refusedAction;
    while (state.batches.isNotEmpty) {
      final batch = state.batches.first;
      try {
        last = await _send(state, batch);
        _settle(state, batch);
        state.batches.removeAt(0);
        await _store.save(state);
      } on AiConversationException catch (e) {
        if (e.statusCode == 404) {
          // The session is gone (expired, abandoned, confirmed elsewhere): nothing queued for it
          // can ever be delivered. The feed is released and the technician told.
          await _store.unlink(state.sessionId);
          throw const AiFeedSessionGoneException();
        }
        if (e.statusCode == 422) {
          // The REQUEST was refused (validation of its shape), not one edit: halving cannot help.
          // Derived edits stop going edits-only and ride in the next turn instead; an explicit
          // action is reported.
          state.batches.removeAt(0);
          for (var i = 0; i < batch.edits.length; i++) {
            if (batch.derived[i]) {
              state.editsOnlyRefused.add(editSignature(batch.edits[i]));
            } else {
              refusedAction = e;
            }
          }
          await _store.save(state);
          continue;
        }
        if (e.statusCode != 400 && e.statusCode != 413) rethrow;
        state.batches.removeAt(0);
        if (batch.edits.length > 1) {
          // Halve it: new keys (a 400 claims nothing on the server), same order, persisted.
          final mid = batch.edits.length ~/ 2;
          state.batches.insertAll(0, [
            AiEditBatch(
              key: _newKey(),
              edits: batch.edits.sublist(0, mid),
              derived: batch.derived.sublist(0, mid),
            ),
            AiEditBatch(
              key: _newKey(),
              edits: batch.edits.sublist(mid),
              derived: batch.derived.sublist(mid),
            ),
          ]);
        } else if (batch.derived.single) {
          state.rejected[editSignature(batch.edits.single)] = e.code ?? e.message;
        } else {
          refusedAction = e; // an explicit action: the technician is told
        }
        await _store.save(state);
      }
    }
    if (refusedAction != null) throw refusedAction;
    return last;
  }

  Future<AiCopilotDraftDto> _send(AiDraftFeedState state, AiEditBatch batch) async {
    var inProgress = 0;
    var concurrent = false;
    while (true) {
      try {
        final result = await _client.syncEdits(
          state.sessionId,
          batch.edits,
          idempotencyKey: batch.key,
        );
        return result.draft;
      } on AiConversationException catch (e) {
        if (e.isTurnInProgress && inProgress < _maxInProgressRetries) {
          inProgress++;
          await Future<void>.delayed(retryDelay);
          continue;
        }
        if (e.isConcurrentUpdate && !concurrent) {
          concurrent = true; // same key: the server replays or applies it once
          continue;
        }
        if (e.isDraftTooLarge || e.isTurnLimitExceeded) {
          state
            ..blocked = true
            ..batches.clear();
          await _store.save(state);
          throw const AiEditSyncBlockedException(_blockedMessage);
        }
        rethrow;
      }
    }
  }

  static void _settle(AiDraftFeedState state, AiEditBatch batch) {
    AiDraftFeed.acknowledgeInto(state, [
      for (var i = 0; i < batch.edits.length; i++)
        if (batch.derived[i]) batch.edits[i],
    ]);
  }
}

final aiDraftFeedStoreProvider = Provider<AiDraftFeedStore>((ref) => AiDraftFeedStore());

final aiDraftFeedProvider = Provider<AiDraftFeed>(
  (ref) => AiDraftFeed(
    db: ref.watch(appDatabaseProvider),
    store: ref.watch(aiDraftFeedStoreProvider),
  ),
);

final aiEditSyncerProvider = Provider<AiEditSyncer>(
  (ref) => AiEditSyncer(
    client: ref.watch(aiApiClientProvider),
    feed: ref.watch(aiDraftFeedProvider),
    store: ref.watch(aiDraftFeedStoreProvider),
  ),
);
