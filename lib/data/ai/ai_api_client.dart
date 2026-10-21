import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dio_client.dart';
import '../api/json_parse.dart';

/// AI report drafting, and the quota it spends.
///
/// ## The quota is the whole company's, and it is spent before the work
///
/// `AiQuotaService.TryConsumeAsync` takes a **tenant** id, not a user id: the monthly allowance
/// belongs to the company, so one technician generating drafts all afternoon exhausts it for
/// everyone. And the controller consumes the quota *before* calling the model — a generation that
/// then fails has still cost one. Both facts have to reach the screen, or a technician cannot make
/// an informed decision about pressing the button.
///
/// ## Two voice paths
///
/// On-device dictation (`DictateButton`, `lib/core/dictation/`, ADR-0017) fills a text field and
/// never leaves the phone. [AiApiClient.transcribe] is the ONLINE path: a recording from
/// `lib/core/audio/` is uploaded to `POST /api/ai/transcribe` and the server returns the
/// transcript plus an `audioRef`.

/// What the company has left this month.
class AiQuotaDto {
  const AiQuotaDto({
    required this.monthlyLimit,
    required this.used,
    required this.remaining,
    this.resetsAt,
  });

  final int monthlyLimit;
  final int used;
  final int remaining;
  final DateTime? resetsAt;

  bool get exhausted => remaining <= 0;

  factory AiQuotaDto.fromJson(Map<String, dynamic> json) => AiQuotaDto(
    monthlyLimit: asIntOr0(json['monthlyLimit']),
    used: asIntOr0(json['used']),
    remaining: asIntOr0(json['remaining']),
    resetsAt: DateTime.tryParse(json['resetsAt'] as String? ?? '')?.toUtc(),
  );
}

/// A drafted rapportino. Suggestions, not a record — nothing here is saved until the technician
/// keeps it.
class AiReportDraftDto {
  const AiReportDraftDto({
    required this.title,
    required this.details,
    required this.modelUsed,
    this.technicianNotes,
    this.suggestedStartedAt,
    this.suggestedEndedAt,
  });

  final String title;
  final String details;

  /// Which model produced this. Shown to the technician: an AI suggestion should say it is one.
  final String modelUsed;

  final String? technicianNotes;
  final DateTime? suggestedStartedAt;
  final DateTime? suggestedEndedAt;

  factory AiReportDraftDto.fromJson(Map<String, dynamic> json) =>
      AiReportDraftDto(
        title: json['title'] as String? ?? '',
        details: json['details'] as String? ?? '',
        modelUsed: json['modelUsed'] as String? ?? '',
        technicianNotes: json['technicianNotes'] as String?,
        suggestedStartedAt: DateTime.tryParse(
          json['suggestedStartedAt'] as String? ?? '',
        )?.toUtc(),
        suggestedEndedAt: DateTime.tryParse(
          json['suggestedEndedAt'] as String? ?? '',
        )?.toUtc(),
      );
}

/// The company's monthly allowance is gone. Carries the reset date so the screen can say when it
/// comes back rather than just refusing.
class AiQuotaExhaustedException implements Exception {
  const AiQuotaExhaustedException({
    this.monthlyLimit,
    this.used,
    this.resetsAt,
  });

  final int? monthlyLimit;
  final int? used;
  final DateTime? resetsAt;

  @override
  String toString() => 'Quota AI esaurita.';
}

/// Any other reason the draft did not happen, already in Italian.
class AiFailure implements Exception {
  const AiFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A conversation-endpoint failure that keeps its HTTP status — the screen needs to react
/// differently to a 409 (stale idempotency-key version: mint a fresh key and let the technician
/// retry) than to any other failure, which a plain [AiFailure] can't express.
class AiConversationException implements Exception {
  const AiConversationException(this.statusCode, this.message, {this.code, this.offline = false});

  final int? statusCode;
  final String message;

  /// The server's stable machine-readable code (`turn_in_progress`, `concurrent_update`,
  /// `draft_too_large`, `turn_limit_exceeded`, ...), when the error body carried one.
  final String? code;

  /// The request never reached the server (no signal, DNS, timeout): the same call may succeed
  /// later, and the AI draft needs a connection.
  final bool offline;

  bool get isStaleVersionConflict => statusCode == 409;

  /// 409: the same Idempotency-Key is still being processed. Retry with the SAME key after a pause.
  bool get isTurnInProgress => statusCode == 409 && code == 'turn_in_progress';

  /// 409: the draft moved on under this request. Refetch it (GET), then retry with the same key.
  bool get isConcurrentUpdate => statusCode == 409 && code == 'concurrent_update';

  /// 409: the draft or the conversation hit a hard cap; retrying cannot help.
  bool get isDraftTooLarge => statusCode == 409 && code == 'draft_too_large';
  bool get isTurnLimitExceeded => statusCode == 409 && code == 'turn_limit_exceeded';

  /// 422: the turn text (or raw transcript) is over the server's per-turn character cap. The
  /// technician can shorten it and send again.
  bool get isTextTooLong => code == textTooLongCode;

  static const textTooLongCode = 'text_too_long';

  @override
  String toString() => message;
}

/// A resolved field's confidence — mirrors backend `ResolutionState` (CandidateFact.cs),
/// on the wire as a string (`[JsonConverter(typeof(JsonStringEnumConverter))]`).
///
/// [needsConfirmation] is a value that came from the ticket record or a plan, never from the
/// operator: it proves nothing until the technician confirms it. Members are only ever APPENDED on
/// the server, so an unknown string (a newer server) parses to [unresolved], never throws.
enum AiResolutionState {
  unresolved,
  resolvedBySystem,
  operatorConfirmed,
  ambiguous,
  conflict,
  needsConfirmation,
}

AiResolutionState _parseResolutionState(Object? s) => switch (s) {
  'ResolvedBySystem' => AiResolutionState.resolvedBySystem,
  'OperatorConfirmed' => AiResolutionState.operatorConfirmed,
  'Ambiguous' => AiResolutionState.ambiguous,
  'Conflict' => AiResolutionState.conflict,
  'NeedsConfirmation' => AiResolutionState.needsConfirmation,
  _ => AiResolutionState.unresolved,
};

/// Where a draft value came from — mirrors backend `FactSource`. [ticketRecord] and [planned] are
/// never evidence that work happened. An unknown string parses to [operatorInput].
enum AiFactSource { operatorInput, taskTapTool, derived, ticketRecord, planned }

AiFactSource _parseFactSource(Object? s) => switch (s) {
  'TaskTapTool' => AiFactSource.taskTapTool,
  'Derived' => AiFactSource.derived,
  'TicketRecord' => AiFactSource.ticketRecord,
  'Planned' => AiFactSource.planned,
  _ => AiFactSource.operatorInput,
};

/// How a turn's text reached the client (request `source`, and each turn of a resumed session).
enum AiTurnSource { typed, voice }

AiTurnSource _parseTurnSource(Object? s) => s == 'Voice' ? AiTurnSource.voice : AiTurnSource.typed;

class AiConversationSessionDto {
  const AiConversationSessionDto({required this.sessionId, this.ticketId, this.cantiereId});

  final String sessionId;
  final String? ticketId;
  final String? cantiereId;

  factory AiConversationSessionDto.fromJson(Map<String, dynamic> json) =>
      AiConversationSessionDto(
        sessionId: json['sessionId'] as String? ?? '',
        ticketId: json['ticketId'] as String?,
        cantiereId: json['cantiereId'] as String?,
      );
}

/// One draft field the model proposed — just enough to render "N punti da chiarire" and gate
/// Confirm on Ambiguous/Conflict. Full provenance (which tool resolved it, candidates) is not
/// shown on mobile — the web copilot's own doc comment covers why the shape carries more than
/// this; this app only needs the count and the blocking states.
class AiCandidateFact {
  const AiCandidateFact({
    required this.field,
    required this.state,
    this.source = AiFactSource.operatorInput,
    this.conflictOperatorValue,
  });

  final String field;
  final AiResolutionState state;
  final AiFactSource source;

  /// For a held removal (`removed.<collection>.<key>`): the name of the entry the technician
  /// removed and the AI proposed again (the server's `conflict.operatorValue`).
  final String? conflictOperatorValue;

  /// A removal the technician made that a later proposal tried to bring back.
  bool get isHeldRemoval => field.startsWith('removed.');

  /// `workers` | `materials` | `activities` | `controlli` for a held removal, else null.
  String? get removedCollection {
    if (!isHeldRemoval) return null;
    final parts = field.split('.');
    return parts.length >= 3 ? parts[1] : null;
  }

  factory AiCandidateFact.fromJson(Map<String, dynamic> json) {
    final provenance = json['provenance'];
    final conflict = json['conflict'];
    final shown = conflict is Map ? conflict['operatorValue'] : null;
    return AiCandidateFact(
      field: json['field'] as String? ?? '',
      state: _parseResolutionState(json['state']),
      source: _parseFactSource(provenance is Map ? provenance['sourceType'] : null),
      conflictOperatorValue: shown is String ? shown : null,
    );
  }
}

class AiDraftWorkerRef {
  const AiDraftWorkerRef({
    required this.userId,
    required this.fullName,
    this.hours,
    required this.state,
    this.source = AiFactSource.operatorInput,
    this.km,
    this.vehicle,
  });

  final String userId;
  final String fullName;
  final double? hours;
  final AiResolutionState state;
  final AiFactSource source;

  /// Only ever stated by the technician (the server never seeds km or a vehicle).
  final double? km;
  final String? vehicle;

  factory AiDraftWorkerRef.fromJson(Map<String, dynamic> json) => AiDraftWorkerRef(
    userId: json['userId'] as String? ?? '',
    fullName: json['fullName'] as String? ?? '',
    hours: asDouble(json['hours']),
    state: _parseResolutionState(json['state']),
    source: _parseFactSource(json['source']),
    km: asDouble(json['km']),
    vehicle: json['vehicle'] is String ? json['vehicle'] as String : null,
  );
}

class AiDraftMaterialUsage {
  const AiDraftMaterialUsage({
    required this.materialId,
    required this.name,
    required this.quantity,
    required this.state,
    this.source = AiFactSource.operatorInput,
    this.unit,
    this.isFreeText = false,
  });

  /// The catalogue id; the server sends the empty guid for a free-text material.
  final String materialId;
  final String name;
  final double quantity;
  final AiResolutionState state;
  final AiFactSource source;
  final String? unit;

  /// No verified catalogue id: the name is what the technician said.
  final bool isFreeText;

  factory AiDraftMaterialUsage.fromJson(Map<String, dynamic> json) => AiDraftMaterialUsage(
    materialId: json['materialId'] as String? ?? '',
    name: json['name'] as String? ?? '',
    quantity: asDoubleOr0(json['quantity']),
    state: _parseResolutionState(json['state']),
    source: _parseFactSource(json['source']),
    unit: json['unit'] is String ? json['unit'] as String : null,
    isFreeText: json['isFreeText'] == true,
  );
}

class AiDraftControlAnswer {
  const AiDraftControlAnswer({
    required this.ticketControlId,
    this.stringValue,
    this.boolValue,
    this.numberValue,
    this.dateValue,
    required this.state,
  });

  final String ticketControlId;
  final String? stringValue;
  final bool? boolValue;
  final double? numberValue;
  final DateTime? dateValue;
  final AiResolutionState state;

  factory AiDraftControlAnswer.fromJson(Map<String, dynamic> json) => AiDraftControlAnswer(
    ticketControlId: json['ticketControlId'] as String? ?? '',
    stringValue: json['stringValue'] as String?,
    boolValue: json['boolValue'] as bool?,
    numberValue: asDouble(json['numberValue']),
    dateValue: json['dateValue'] is String ? DateTime.tryParse(json['dateValue'] as String) : null,
    state: _parseResolutionState(json['state']),
  );

  /// A short human-readable answer, for a one-line list row.
  String describe() {
    if (stringValue != null) return stringValue!;
    if (boolValue != null) return boolValue! ? 'Sì' : 'No';
    if (numberValue != null) return numberValue!.toString();
    return '—';
  }
}

/// One activity the model resolved for the draft — mirrors backend `DraftActivity`
/// (Orchestration/ReportDraftDto.cs). `AiConversationsController.Confirm` builds the created
/// Report's Title/Details directly from these, so this is the exact text that becomes the
/// rapportino's title/description; the technician needs to see it before confirming.
class AiDraftActivity {
  const AiDraftActivity({
    required this.description,
    this.hours,
    required this.state,
    this.source = AiFactSource.operatorInput,
  });

  final String description;
  final double? hours;
  final AiResolutionState state;
  final AiFactSource source;

  factory AiDraftActivity.fromJson(Map<String, dynamic> json) => AiDraftActivity(
    description: json['description'] as String? ?? '',
    hours: asDouble(json['hours']),
    state: _parseResolutionState(json['state']),
    source: _parseFactSource(json['source']),
  );
}

/// The copilot's structured draft — mirrors backend `ReportDraftDto` (Orchestration/ReportDraftDto.cs).
class AiCopilotDraftDto {
  const AiCopilotDraftDto({
    this.diagnosi,
    this.soluzione,
    this.customerSignoffText,
    required this.workers,
    required this.materials,
    required this.controlli,
    required this.activities,
    required this.openItems,
  });

  final String? diagnosi;
  final String? soluzione;
  final String? customerSignoffText;
  final List<AiDraftWorkerRef> workers;
  final List<AiDraftMaterialUsage> materials;
  final List<AiDraftControlAnswer> controlli;
  final List<AiDraftActivity> activities;
  final List<AiCandidateFact> openItems;

  static const empty = AiCopilotDraftDto(
    workers: [],
    materials: [],
    controlli: [],
    activities: [],
    openItems: [],
  );

  bool get hasBlockingOpenItems => openItems.any(
    (f) => f.state == AiResolutionState.ambiguous || f.state == AiResolutionState.conflict,
  );

  factory AiCopilotDraftDto.fromJson(Map<String, dynamic> json) => AiCopilotDraftDto(
    diagnosi: json['diagnosi'] as String?,
    soluzione: json['soluzione'] as String?,
    customerSignoffText: json['customerSignoffText'] as String?,
    workers: ((json['workers'] as List<dynamic>?) ?? [])
        .map((w) => AiDraftWorkerRef.fromJson(w as Map<String, dynamic>))
        .toList(),
    materials: ((json['materials'] as List<dynamic>?) ?? [])
        .map((m) => AiDraftMaterialUsage.fromJson(m as Map<String, dynamic>))
        .toList(),
    controlli: ((json['controlli'] as List<dynamic>?) ?? [])
        .map((c) => AiDraftControlAnswer.fromJson(c as Map<String, dynamic>))
        .toList(),
    activities: ((json['activities'] as List<dynamic>?) ?? [])
        .map((a) => AiDraftActivity.fromJson(a as Map<String, dynamic>))
        .toList(),
    openItems: ((json['openItems'] as List<dynamic>?) ?? [])
        .map((f) => AiCandidateFact.fromJson(f as Map<String, dynamic>))
        .toList(),
  );
}

class AiConversationTurnResult {
  const AiConversationTurnResult({required this.assistantReplyText, required this.draft});

  final String assistantReplyText;
  final AiCopilotDraftDto draft;

  factory AiConversationTurnResult.fromJson(Map<String, dynamic> json) =>
      AiConversationTurnResult(
        assistantReplyText: json['assistantReplyText'] as String? ?? '',
        draft: AiCopilotDraftDto.fromJson(
          (json['draft'] as Map<String, dynamic>?) ?? const {},
        ),
      );
}

/// One value the technician set, accepted or removed by hand — backend `ConfirmedEditDto`
/// (`AiConversationTurnRequest.ConfirmedEdits`). The server folds it as `OperatorConfirmed`
/// before the model runs, so a later voice turn that disagrees becomes a flagged conflict instead
/// of overwriting it.
///
/// [kind]: `worker` | `material` | `activity` | `control` | `materialiNotRequired`. Properties:
/// worker `hours`/`km` (number), `vehicle` (string); material `quantity` (number), `unit`
/// (string); activity `hours`; control `stringValue`/`boolValue`/`dateValue`/`numberValue`. No
/// [property] and no [value] = "accepted as shown" (confirms every planned value of the entry).
/// [remove] = the removal is itself confirmed: a later proposal for the entry is held, never
/// re-added.
class AiConfirmedEdit {
  const AiConfirmedEdit({
    required this.kind,
    this.id,
    this.name,
    this.property,
    this.value,
    this.remove = false,
  });

  static const kindWorker = 'worker';
  static const kindMaterial = 'material';
  static const kindActivity = 'activity';
  static const kindControl = 'control';

  /// Server cap per request (`ConfirmedEditValidator.MaxEdits`).
  static const maxPerRequest = 50;

  final String kind;
  final String? id;
  final String? name;
  final String? property;

  /// A JSON scalar: num, bool or String (an ISO date for `dateValue`).
  final Object? value;
  final bool remove;

  static const Set<String> wireKeys = {'kind', 'id', 'name', 'property', 'value', 'remove'};

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'id': ?id,
    'name': ?name,
    'property': ?property,
    'value': ?value,
    'remove': remove,
  };

  factory AiConfirmedEdit.fromJson(Map<String, dynamic> json) => AiConfirmedEdit(
    kind: json['kind'] as String? ?? '',
    id: json['id'] as String?,
    name: json['name'] as String?,
    property: json['property'] as String?,
    value: json['value'],
    remove: json['remove'] == true,
  );

  @override
  bool operator ==(Object other) =>
      other is AiConfirmedEdit &&
      other.kind == kind &&
      other.id == id &&
      other.name == name &&
      other.property == property &&
      other.value == value &&
      other.remove == remove;

  @override
  int get hashCode => Object.hash(kind, id, name, property, value, remove);

  @override
  String toString() => 'AiConfirmedEdit(${toJson()})';
}

/// One visible turn of a resumed session: text and how it arrived, never tool calls.
class AiConversationTurn {
  const AiConversationTurn({
    required this.turnId,
    required this.role,
    required this.text,
    required this.source,
    this.at,
  });

  final String turnId;

  /// `Operator` or `Assistant` (any other string is kept as is and rendered as the assistant).
  final String role;
  final String text;
  final AiTurnSource source;
  final DateTime? at;

  bool get isOperator => role == 'Operator';

  factory AiConversationTurn.fromJson(Map<String, dynamic> json) => AiConversationTurn(
    turnId: json['turnId'] as String? ?? '',
    role: json['role'] as String? ?? '',
    text: json['text'] as String? ?? '',
    source: _parseTurnSource(json['source']),
    at: DateTime.tryParse(json['at'] as String? ?? '')?.toUtc(),
  );
}

/// `GET /api/ai/conversations/{id}`: the durable draft plus what was said, enough to resume on
/// any device. [expiresAtUtc] is the date the inactive draft is deleted.
class AiConversationDetailDto {
  const AiConversationDetailDto({
    required this.sessionId,
    this.ticketId,
    required this.draft,
    required this.turns,
    required this.version,
    required this.expiresAtUtc,
    this.authorName,
  });

  final String sessionId;
  final String? ticketId;
  final AiCopilotDraftDto draft;
  final List<AiConversationTurn> turns;
  final int version;
  final DateTime expiresAtUtc;
  final String? authorName;

  factory AiConversationDetailDto.fromJson(Map<String, dynamic> json) {
    final author = json['author'];
    return AiConversationDetailDto(
      sessionId: json['sessionId'] as String? ?? '',
      ticketId: json['ticketId'] as String?,
      draft: AiCopilotDraftDto.fromJson((json['draft'] as Map<String, dynamic>?) ?? const {}),
      turns: ((json['turns'] as List<dynamic>?) ?? [])
          .whereType<Map<String, dynamic>>()
          .map(AiConversationTurn.fromJson)
          .toList(),
      version: asIntOr0(json['version']),
      // Far in the future when absent or unreadable: an unknown expiry must never raise a warning.
      expiresAtUtc:
          DateTime.tryParse(json['expiresAtUtc'] as String? ?? '')?.toUtc() ??
          DateTime.utc(9999),
      authorName: author is Map ? author['fullName'] as String? : null,
    );
  }
}

/// One resolved technician line. Mirror of backend `AiResolvedStaff`.
///
/// Deliberately narrower than `SubmitReportStaffDto`: the server builds these from a plan that
/// never carries `costPerKm`, `startTime`, `endTime` or `pauseMinutes`, so those are left at their
/// column defaults rather than round-tripped as nulls.
class AiResolvedStaff {
  const AiResolvedStaff({
    required this.userId,
    this.hoursWorked,
    this.kmTraveled = 0,
    this.vehicle,
  });

  final String userId;
  final double? hoursWorked;
  final double kmTraveled;
  final String? vehicle;

  static const Set<String> wireKeys = {'userId', 'hoursWorked', 'kmTraveled', 'vehicle'};

  factory AiResolvedStaff.fromJson(Map<String, dynamic> json) => AiResolvedStaff(
    userId: json['userId'] as String? ?? '',
    hoursWorked: asDouble(json['hoursWorked']),
    kmTraveled: asDoubleOr0(json['kmTraveled']),
    vehicle: json['vehicle'] as String?,
  );
}

/// One resolved material line. Mirror of backend `AiResolvedMaterial`.
///
/// NOT `AiDraftMaterialUsage`: that reads `materialId` and `name`, this reads `materialeId` and
/// `freeTextName`. Exactly one of [materialeId] / [freeTextName] is meaningful — a catalogue id, or
/// a name the operator dictated that no catalogue lookup matched. [notes] carries the
/// "Da verificare" marker on the free-text path, which is the server telling the technician, on the
/// row itself, that the line needs checking.
class AiResolvedMaterial {
  const AiResolvedMaterial({
    this.materialeId,
    this.freeTextName,
    required this.quantity,
    this.unitOfMeasure,
    this.notes,
  });

  final String? materialeId;
  final String? freeTextName;
  final double quantity;
  final String? unitOfMeasure;
  final String? notes;

  static const Set<String> wireKeys = {
    'materialeId',
    'freeTextName',
    'quantity',
    'unitOfMeasure',
    'notes',
  };

  factory AiResolvedMaterial.fromJson(Map<String, dynamic> json) => AiResolvedMaterial(
    materialeId: json['materialeId'] as String?,
    freeTextName: json['freeTextName'] as String?,
    quantity: asDoubleOr0(json['quantity']),
    unitOfMeasure: json['unitOfMeasure'] as String?,
    notes: json['notes'] as String?,
  );
}

/// One resolved checklist answer. Mirror of backend `AiResolvedControl`.
///
/// [ticketControlId] is the **TicketControl** — this job's copy of a checklist item — not the
/// template control it came from. The server validates ownership on submit, so a mismatched id
/// fails the whole submission rather than quietly recording nothing.
class AiResolvedControl {
  const AiResolvedControl({
    required this.ticketControlId,
    this.stringValue,
    this.boolValue,
    this.dateValue,
    this.numberValue,
    this.note,
  });

  final String ticketControlId;
  final String? stringValue;
  final bool? boolValue;
  final DateTime? dateValue;
  final double? numberValue;
  final String? note;

  static const Set<String> wireKeys = {
    'ticketControlId',
    'stringValue',
    'boolValue',
    'dateValue',
    'numberValue',
    'note',
  };

  factory AiResolvedControl.fromJson(Map<String, dynamic> json) => AiResolvedControl(
    ticketControlId: json['ticketControlId'] as String? ?? '',
    stringValue: json['stringValue'] as String?,
    boolValue: json['boolValue'] as bool?,
    dateValue: json['dateValue'] != null
        ? DateTime.tryParse(json['dateValue'] as String)
        : null,
    numberValue: asDouble(json['numberValue']),
    note: json['note'] as String?,
  );
}

/// What `POST /api/ai/conversations/{id}/confirm` returns: the draft resolved against real tenant
/// data, and nothing written (spec §5.4). Mirror of backend `AiConversationConfirmResponse`.
///
/// It is NOT a created report: there is no `reportId` and no `replayed`, because confirming twice
/// returns the same draft. The client owns the write that follows, and owns [materialiNotRequired]
/// and the provenance flag (`isAiAssisted`), which the response deliberately does not carry.
///
/// [locationId] may be null: the server normalises its own `Guid.Empty` "never resolved" sentinel
/// to null rather than hand back an id nothing downstream would reject. Never substitute a value
/// for it — see the submit path's nullable handling in the editor screen.
///
/// [warnings] is operator-facing and empty when everything resolved; it replaces the per-item
/// `AiResolutionState` the draft summary uses, because resolution is what produced this response.
class AiConversationConfirmResponse {
  const AiConversationConfirmResponse({
    required this.title,
    this.details,
    this.materialiNotRequired = false,
    this.customerSignoffText,
    this.ticketId,
    this.cantiereId,
    this.locationId,
    this.staff = const [],
    this.materials = const [],
    this.controlli = const [],
    this.warnings = const [],
  });

  final String title;
  final String? details;
  final bool materialiNotRequired;
  final String? customerSignoffText;
  final String? ticketId;
  final String? cantiereId;
  final String? locationId;
  final List<AiResolvedStaff> staff;
  final List<AiResolvedMaterial> materials;
  final List<AiResolvedControl> controlli;
  final List<String> warnings;

  static const Set<String> wireKeys = {
    'title',
    'details',
    'materialiNotRequired',
    'customerSignoffText',
    'ticketId',
    'cantiereId',
    'locationId',
    'staff',
    'materials',
    'controlli',
    'warnings',
  };

  factory AiConversationConfirmResponse.fromJson(Map<String, dynamic> json) =>
      AiConversationConfirmResponse(
        title: json['title'] as String? ?? '',
        details: json['details'] as String?,
        materialiNotRequired: json['materialiNotRequired'] as bool? ?? false,
        customerSignoffText: json['customerSignoffText'] as String?,
        ticketId: json['ticketId'] as String?,
        cantiereId: json['cantiereId'] as String?,
        locationId: json['locationId'] as String?,
        staff: ((json['staff'] as List<dynamic>?) ?? [])
            .map((s) => AiResolvedStaff.fromJson(s as Map<String, dynamic>))
            .toList(),
        materials: ((json['materials'] as List<dynamic>?) ?? [])
            .map((m) => AiResolvedMaterial.fromJson(m as Map<String, dynamic>))
            .toList(),
        controlli: ((json['controlli'] as List<dynamic>?) ?? [])
            .map((c) => AiResolvedControl.fromJson(c as Map<String, dynamic>))
            .toList(),
        warnings: ((json['warnings'] as List<dynamic>?) ?? [])
            .map((w) => w.toString())
            .toList(),
      );
}

/// Per-request limits for `transcribe` only (the shared Dio allows 30 s to receive, with no send
/// limit). The server reads the whole upload and calls the transcription provider before it
/// answers, so a 5 minute recording legitimately takes far longer than 30 s.
const Duration transcribeSendTimeout = Duration(minutes: 5);

/// Per-request limits for a turn. The server may work up to 45 s on one turn
/// (`AiAgentLimits.MaxExecutionTimePerTurn`); the shared Dio's 30 s would abandon a turn the
/// server is still completing (and charging).
const Duration turnSendTimeout = Duration(seconds: 60);
const Duration turnReceiveTimeout = Duration(seconds: 60);

/// The server's per-turn text cap (`AiAgentLimits.MaxOperatorTurnCharacters`).
const int maxTurnCharacters = 8000;
const Duration transcribeReceiveTimeout = Duration(minutes: 4);

/// What `POST /api/ai/transcribe` returns: the transcript and the id of the retained audio.
class AiTranscription {
  const AiTranscription({required this.transcript, required this.audioRef});

  final String transcript;
  final String audioRef;

  factory AiTranscription.fromJson(Map<String, dynamic> json) => AiTranscription(
    transcript: json['transcript'] as String? ?? '',
    audioRef: json['audioRef'] as String? ?? '',
  );
}

/// Why an upload for transcription did not produce a transcript. Quota exhaustion (429) is
/// [AiQuotaExhaustedException], not a value here.
enum AiTranscribeError {
  /// 404: `Ai:VoiceCapture:Enabled` is off on the server.
  voiceDisabled,

  /// 403: AI drafting is switched off for the company.
  aiDisabled,
  audioTypeMismatch,
  audioUnrecognised,
  audioTooLong,
  audioTooShort,
  audioTooLarge,
  audioTypeNotAllowed,

  /// 400 without a recognised stable code: repeating the same upload cannot help.
  badRequest,

  /// 403 that is a plain permission failure (not the tenant's AI switch).
  forbidden,

  /// The request ran out of time (upload or waiting for the transcript). Retry with the SAME key:
  /// the server may already have finished it and will replay the result.
  timeout,
  offline,
  unavailable,
}

class AiTranscribeException implements Exception {
  const AiTranscribeException(this.error, this.message);

  final AiTranscribeError error;
  final String message;

  /// True when the SAME file may succeed later (connection, server hiccup). False when the audio
  /// itself or the feature switch is the problem: repeating the upload cannot help.
  bool get retryable =>
      error == AiTranscribeError.offline ||
      error == AiTranscribeError.timeout ||
      error == AiTranscribeError.unavailable;

  @override
  String toString() => message;
}

class AiApiClient {
  AiApiClient(this._dio);

  final Dio _dio;

  /// GET /api/ai/quota
  Future<AiQuotaDto> getQuota() async {
    final response = await _dio.get<Map<String, dynamic>>('/api/ai/quota');
    final data = response.data;
    if (data == null) throw const AiFailure('Risposta vuota dal servizio AI.');
    return AiQuotaDto.fromJson(data);
  }

  /// POST /api/ai/reports/draft
  ///
  /// All four fields are optional on the wire: the server resolves context in tiers — schedule,
  /// then ticket, then cantiere, then the raw transcript — and uses whichever most-specific one is
  /// present. It only 400s when none of the four are given, so the caller just needs to pass
  /// through whatever this rapportino actually has; there is no single required field anymore.
  Future<AiReportDraftDto> generateDraft({
    String? scheduleId,
    String? ticketId,
    String? cantiereId,
    String? voiceTranscript,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/ai/reports/draft',
        data: {
          'scheduleId': ?scheduleId,
          'ticketId': ?ticketId,
          'cantiereId': ?cantiereId,
          'voiceTranscript': ?voiceTranscript,
        },
      );
      final data = response.data;
      if (data == null) {
        throw const AiFailure('Risposta vuota dal servizio AI.');
      }
      return AiReportDraftDto.fromJson(data);
    } on DioException catch (e) {
      throw _translate(e);
    }
  }

  // ── AI Copilot conversation (POST /api/ai/conversations/...) ──────────────────
  //
  // Multi-turn counterpart to [generateDraft] above — the model calls TaskTap tools to verify
  // people/hours/materials/checklist items against real data across several turns instead of one
  // shot. This endpoint itself is text-only (no audio field on the wire), but the screen built on
  // top of it is not voice-less: dictation via `DictateButton` (on-device, per ADR-0017) fills the
  // text field before it's sent here — see this file's own "Server-upload transcription is
  // deliberately absent" note, and `ai_copilot_screen.dart`'s own comment on the same point.

  /// POST /api/ai/conversations — starts a session bound to at most one of ticketId/cantiereId.
  Future<AiConversationSessionDto> startConversation({
    String? ticketId,
    String? cantiereId,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/ai/conversations',
        data: {'ticketId': ?ticketId, 'cantiereId': ?cantiereId},
      );
      final data = response.data;
      if (data == null) throw const AiFailure('Risposta vuota dal servizio AI.');
      return AiConversationSessionDto.fromJson(data);
    } on DioException catch (e) {
      throw _translateConversation(e);
    }
  }

  /// GET /api/ai/conversations?ticketId= — the caller's live session for that ticket, or null (404).
  Future<String?> resumeConversation(String ticketId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/ai/conversations',
        queryParameters: {'ticketId': ticketId},
      );
      final id = response.data?['sessionId'] as String?;
      return (id == null || id.isEmpty) ? null : id;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw _translateConversation(e);
    }
  }

  /// GET /api/ai/conversations/{id} — the draft, the turns and the expiry.
  Future<AiConversationDetailDto> getConversation(String sessionId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/api/ai/conversations/$sessionId');
      final data = response.data;
      if (data == null) throw const AiFailure('Risposta vuota dal servizio AI.');
      return AiConversationDetailDto.fromJson(data);
    } on DioException catch (e) {
      throw _translateConversation(e);
    }
  }

  /// POST /api/ai/conversations/{id}/turns — one utterance, typed or transcribed.
  ///
  /// [idempotencyKey] (sent as the `Idempotency-Key` header) must be generated ONCE per logical
  /// turn and reused unchanged on every retry: the server then replays the original response
  /// instead of applying (and charging) the turn twice. [replacesTurnId] marks a correction of an
  /// earlier operator turn. [confirmedEdits] is for the editor sync (Task 12).
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
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/ai/conversations/$sessionId/turns',
        data: {
          'text': text,
          'source': source == AiTurnSource.voice ? 'Voice' : 'Typed',
          'audioRef': ?audioRef,
          'rawTranscript': ?rawTranscript,
          'replacesTurnId': ?replacesTurnId,
          'confirmedEdits': ?confirmedEdits,
        },
        options: Options(
          headers: {'Idempotency-Key': idempotencyKey},
          sendTimeout: turnSendTimeout,
          receiveTimeout: turnReceiveTimeout,
        ),
      );
      final data = response.data;
      if (data == null) throw const AiFailure('Risposta vuota dal servizio AI.');
      return AiConversationTurnResult.fromJson(data);
    } on DioException catch (e) {
      throw _translateConversation(e);
    }
  }

  /// POST /api/ai/conversations/{id}/turns with EMPTY text: an edits-only sync. The server folds
  /// [edits] as operator-confirmed facts and never calls the model or charges for it. At most
  /// [AiConfirmedEdit.maxPerRequest] per call. [idempotencyKey] is the batch's own key, reused
  /// unchanged on every retry of the same batch.
  Future<AiConversationTurnResult> syncEdits(
    String sessionId,
    List<AiConfirmedEdit> edits, {
    required String idempotencyKey,
  }) => postTurn(
    sessionId,
    text: '',
    confirmedEdits: [for (final e in edits) e.toJson()],
    idempotencyKey: idempotencyKey,
  );

  /// POST /api/ai/conversations/{id}/turns — one operator utterance.
  Future<AiConversationTurnResult> sendTurn(String sessionId, String text) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/ai/conversations/$sessionId/turns',
        data: {'text': text},
      );
      final data = response.data;
      if (data == null) throw const AiFailure('Risposta vuota dal servizio AI.');
      return AiConversationTurnResult.fromJson(data);
    } on DioException catch (e) {
      throw _translateConversation(e);
    }
  }

  /// POST /api/ai/conversations/{id}/confirm — resolves the draft against real tenant data and
  /// persists nothing (spec §5.4). The client owns the write that follows.
  ///
  /// [idempotencyKey] should be a fresh id per confirm *attempt* (retried unchanged on a plain
  /// retry, regenerated by the caller after a 409 — mirrors the backend's own reuse contract,
  /// documented on `AiConversationsController.Confirm`). The header is sent but the server takes no
  /// header parameter today, so it is advisory; `request_body_contract_test.dart` records that the
  /// request carries nothing else.
  Future<AiConversationConfirmResponse> confirmConversation(
    String sessionId, {
    required String idempotencyKey,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/ai/conversations/$sessionId/confirm',
        options: Options(headers: {'Idempotency-Key': idempotencyKey}),
      );
      final data = response.data;
      if (data == null) throw const AiFailure('Risposta vuota dal servizio AI.');
      return AiConversationConfirmResponse.fromJson(data);
    } on DioException catch (e) {
      throw _translateConversation(e);
    }
  }

  /// POST /api/ai/transcribe — multipart field `audio` (m4a, sent as audio/mp4). The server sniffs
  /// the container from the bytes and rejects a declared type that does not match.
  ///
  /// [idempotencyKey] must be generated once per recording and reused on every retry: the server
  /// then returns the same `audioRef` without transcribing or charging again.
  Future<AiTranscription> transcribe(File audio, {required String idempotencyKey}) async {
    try {
      final form = FormData.fromMap({
        'audio': await MultipartFile.fromFile(
          audio.path,
          filename: 'voice.m4a',
          contentType: DioMediaType('audio', 'mp4'),
        ),
      });
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/ai/transcribe',
        data: form,
        options: Options(
          headers: {'Idempotency-Key': idempotencyKey},
          sendTimeout: transcribeSendTimeout,
          receiveTimeout: transcribeReceiveTimeout,
        ),
      );
      final data = response.data;
      if (data == null) throw const AiFailure('Risposta vuota dal servizio AI.');
      return AiTranscription.fromJson(data);
    } on DioException catch (e) {
      throw _translateTranscribe(e);
    }
  }

  static Exception _translateTranscribe(DioException e) {
    final status = e.response?.statusCode;
    final body = e.response?.data;
    final map = body is Map<String, dynamic> ? body : null;

    if (status == 429) {
      return AiQuotaExhaustedException(
        monthlyLimit: asInt(map?['monthlyLimit']),
        used: asInt(map?['used']),
        resetsAt: DateTime.tryParse(map?['resetsAt'] as String? ?? '')?.toUtc(),
      );
    }
    if (status == null &&
        (e.type == DioExceptionType.sendTimeout || e.type == DioExceptionType.receiveTimeout)) {
      return const AiTranscribeException(
        AiTranscribeError.timeout,
        'La trascrizione sta impiegando troppo tempo. La registrazione è salvata: riprova.',
      );
    }
    if (status == null &&
        (e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout)) {
      return const AiTranscribeException(
        AiTranscribeError.offline,
        'Nessuna connessione. La registrazione è salvata: riprova quando torna la rete.',
      );
    }
    if (status == 404) {
      return const AiTranscribeException(
        AiTranscribeError.voiceDisabled,
        'La trascrizione vocale non è attiva per questa azienda.',
      );
    }
    if (status == 403) {
      // The controller's AI-switch refusal is `{error: "La generazione di bozze con AI è
      // disattivata ..."}`; any other 403 is a permission/entitlement failure.
      final text = (map?['error'] as String?) ?? '';
      if (text.contains('disattivata')) {
        return const AiTranscribeException(
          AiTranscribeError.aiDisabled,
          'La bozza con AI è disattivata per questa azienda.',
        );
      }
      return const AiTranscribeException(
        AiTranscribeError.forbidden,
        'Non hai i permessi per usare la trascrizione vocale.',
      );
    }
    if (status == 413) {
      return const AiTranscribeException(
        AiTranscribeError.audioTooLarge,
        'Il file audio è troppo grande.',
      );
    }
    if (status == 400) {
      final code = map?['error'] as String?;
      final reason = switch (code) {
        'audio_type_mismatch' => (
          AiTranscribeError.audioTypeMismatch,
          'Il formato dell\'audio non è riconosciuto dal server.',
        ),
        'audio_unrecognised' => (
          AiTranscribeError.audioUnrecognised,
          'Il file audio non è leggibile.',
        ),
        'audio_too_long' => (
          AiTranscribeError.audioTooLong,
          'La registrazione è troppo lunga.',
        ),
        'audio_too_short' => (
          AiTranscribeError.audioTooShort,
          'La registrazione è troppo breve.',
        ),
        'audio_too_large' => (
          AiTranscribeError.audioTooLarge,
          'Il file audio è troppo grande.',
        ),
        'audio_type_not_allowed' => (
          AiTranscribeError.audioTypeNotAllowed,
          'Il formato audio non è accettato.',
        ),
        _ => null,
      };
      if (reason != null) return AiTranscribeException(reason.$1, reason.$2);
      return const AiTranscribeException(
        AiTranscribeError.badRequest,
        'Il server ha rifiutato la registrazione.',
      );
    }
    return const AiTranscribeException(
      AiTranscribeError.unavailable,
      'Il servizio di trascrizione non ha risposto. Riprova più tardi.',
    );
  }

  /// DELETE /api/ai/conversations/{id}, reporting whether the session is gone afterwards (a 404
  /// counts: it already was). Never throws.
  Future<bool> tryAbandonConversation(String sessionId) async {
    try {
      await _dio.delete<void>('/api/ai/conversations/$sessionId');
      return true;
    } on DioException catch (e) {
      return e.response?.statusCode == 404;
    } catch (_) {
      return false;
    }
  }

  /// DELETE /api/ai/conversations/{id} — abandon. Best-effort: a session that's already gone
  /// (already confirmed, expired) is not a failure from the caller's point of view.
  Future<void> abandonConversation(String sessionId) async {
    try {
      await _dio.delete<void>('/api/ai/conversations/$sessionId');
    } catch (_) {
      // best-effort — see doc comment above
    }
  }

  static String _italian400(String? code) => switch (code) {
    'turn_empty' => 'L\'aggiornamento è vuoto: scrivi o registra qualcosa.',
    'audio_ref_invalid' =>
      'La registrazione non è più disponibile sul server: registrala di nuovo o scrivi '
          'l\'aggiornamento.',
    'too_many_edits' => 'Troppe modifiche in una volta: riprova.',
    'edit_reference_not_found' =>
      'Una modifica riguarda una voce che non esiste più o non appartiene a questo ticket.',
    'edit_value_invalid' || 'edit_property_unknown' || 'edit_kind_unknown' || 'edit_id_required' =>
      'Una modifica fatta nel rapportino non è stata accettata dal server.',
    'edit_sync_extras_not_allowed' => 'Le modifiche non possono essere inviate insieme alla voce.',
    _ => 'Il server ha rifiutato l\'aggiornamento. Riprova; se il problema resta, continua a mano '
        'nel rapportino.',
  };

  static Exception _translate(DioException e) {
    final status = e.response?.statusCode;
    final body = e.response?.data;
    final map = body is Map<String, dynamic> ? body : null;

    if (status == 429) {
      return AiQuotaExhaustedException(
        monthlyLimit: asInt(map?['monthlyLimit']),
        used: asInt(map?['used']),
        resetsAt: DateTime.tryParse(map?['resetsAt'] as String? ?? '')?.toUtc(),
      );
    }

    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return const AiFailure(
        'Nessuna connessione. La bozza AI richiede la rete: '
        'compila il rapportino a mano e riprova più tardi.',
      );
    }

    // The controller answers 400 with the domain reason as a bare string — "schedule not found",
    // "no ticket linked". Those are written for an API consumer, so they are not shown raw.
    if (status == 400) {
      return const AiFailure(
        'Non ci sono abbastanza informazioni sull\'intervento per generare una bozza.',
      );
    }

    return const AiFailure(
      'Il servizio AI non ha risposto. Riprova più tardi.',
    );
  }

  /// As [_translate], but for the conversation endpoints — keeps the HTTP status (see
  /// [AiConversationException]'s own doc comment for why) instead of collapsing it into one
  /// generic [AiFailure].
  static Exception _translateConversation(DioException e) {
    final status = e.response?.statusCode;
    final body = e.response?.data;
    final map = body is Map<String, dynamic> ? body : null;

    if (status == 429) {
      return AiQuotaExhaustedException(
        monthlyLimit: asInt(map?['monthlyLimit']),
        used: asInt(map?['used']),
        resetsAt: DateTime.tryParse(map?['resetsAt'] as String? ?? '')?.toUtc(),
      );
    }

    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return AiConversationException(
        status,
        'Nessuna connessione. Il copilot AI richiede la rete.',
        offline: true,
      );
    }

    if (status == 404) {
      return AiConversationException(
        status,
        'La conversazione non esiste più — è scaduta o è già stata confermata.',
      );
    }

    if (status == 403) {
      return AiConversationException(status, 'Non hai i permessi per questa conversazione.');
    }

    if (status == 409) {
      // ProblemDetails carries the stable code under `code`; older shapes used `error`.
      final rawCode = map?['code'] ?? map?['error'];
      final code = rawCode is String ? rawCode : null;
      return AiConversationException(
        status,
        switch (code) {
          'turn_in_progress' => 'L\'aggiornamento precedente è ancora in elaborazione.',
          'concurrent_update' => 'La bozza è stata modificata da un altro dispositivo.',
          'draft_too_large' =>
            'La bozza è diventata troppo grande: apri il rapportino e completalo a mano.',
          'turn_limit_exceeded' =>
            'Questa conversazione ha raggiunto il limite di aggiornamenti.',
          _ => 'La bozza è cambiata da quando hai provato a confermare — riprova.',
        },
        code: code,
      );
    }

    if (status == 400) {
      // The AI endpoints answer 400 with `{error: <stable code>, message}`: keep the code so a
      // caller can tell WHICH refusal it was (an edit the server will never accept, say), and
      // show an Italian sentence, never the raw code.
      final rawCode = map?['error'];
      final code = rawCode is String ? rawCode : null;
      return AiConversationException(status, _italian400(code), code: code);
    }

    if (status == 422) {
      // The validation filter's ProblemDetails: `{code: 'validation_failed', errors: {Text: [...]}}`.
      final errors = map?['errors'];
      final tooLong =
          errors is Map &&
          errors.entries.any(
            (e) =>
                ['text', 'rawtranscript'].contains(e.key.toString().toLowerCase()) &&
                '${e.value}'.contains('exceed'),
          );
      if (tooLong) {
        return AiConversationException(
          status,
          'Il testo è troppo lungo per un solo aggiornamento (massimo $maxTurnCharacters '
          'caratteri): accorcialo e invialo di nuovo.',
          code: AiConversationException.textTooLongCode,
        );
      }
      final rawCode = map?['code'];
      return AiConversationException(
        status,
        'Il server ha rifiutato i dati inviati. Controlla l\'aggiornamento e riprova; se il '
        'problema resta, continua a mano nel rapportino.',
        code: rawCode is String ? rawCode : 'validation_failed',
      );
    }

    return AiConversationException(status, 'Il servizio AI non ha risposto. Riprova più tardi.');
  }
}

final aiApiClientProvider = Provider<AiApiClient>((ref) {
  return AiApiClient(ref.watch(dioProvider));
});

/// The company's remaining AI allowance.
///
/// Autodisposed and re-read after each generation, because the number it shows is shared: another
/// technician spending it is exactly the case where a stale figure misleads.
final aiQuotaProvider = FutureProvider.autoDispose<AiQuotaDto>((ref) {
  return ref.watch(aiApiClientProvider).getQuota();
});
