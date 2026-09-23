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
/// ## Transcription is deliberately absent
///
/// `POST /api/ai/transcribe` exists and takes a multipart audio file, but this app has no
/// audio-recording dependency and no microphone permission declared on either platform. Adding
/// both is a platform change — a new package, an Android manifest entry and an iOS usage
/// description — not a wiring task, and not one to make weeks before a pilot without deciding it
/// first. A client method with no possible caller would have been dead code pretending to be
/// coverage, so it is left out and recorded in `docs/redesign-handoff.md` instead.

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
  const AiConversationException(this.statusCode, this.message);

  final int? statusCode;
  final String message;

  bool get isStaleVersionConflict => statusCode == 409;

  @override
  String toString() => message;
}

/// A resolved field's confidence — mirrors backend `ResolutionState` (CandidateFact.cs),
/// on the wire as a string (`[JsonConverter(typeof(JsonStringEnumConverter))]`).
enum AiResolutionState { unresolved, resolvedBySystem, operatorConfirmed, ambiguous, conflict }

AiResolutionState _parseResolutionState(String? s) => switch (s) {
  'ResolvedBySystem' => AiResolutionState.resolvedBySystem,
  'OperatorConfirmed' => AiResolutionState.operatorConfirmed,
  'Ambiguous' => AiResolutionState.ambiguous,
  'Conflict' => AiResolutionState.conflict,
  _ => AiResolutionState.unresolved,
};

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
  const AiCandidateFact({required this.field, required this.state});

  final String field;
  final AiResolutionState state;

  factory AiCandidateFact.fromJson(Map<String, dynamic> json) => AiCandidateFact(
    field: json['field'] as String? ?? '',
    state: _parseResolutionState(json['state'] as String?),
  );
}

class AiDraftWorkerRef {
  const AiDraftWorkerRef({
    required this.userId,
    required this.fullName,
    this.hours,
    required this.state,
  });

  final String userId;
  final String fullName;
  final double? hours;
  final AiResolutionState state;

  factory AiDraftWorkerRef.fromJson(Map<String, dynamic> json) => AiDraftWorkerRef(
    userId: json['userId'] as String? ?? '',
    fullName: json['fullName'] as String? ?? '',
    hours: asDouble(json['hours']),
    state: _parseResolutionState(json['state'] as String?),
  );
}

class AiDraftMaterialUsage {
  const AiDraftMaterialUsage({
    required this.materialId,
    required this.name,
    required this.quantity,
    required this.state,
  });

  final String materialId;
  final String name;
  final double quantity;
  final AiResolutionState state;

  factory AiDraftMaterialUsage.fromJson(Map<String, dynamic> json) => AiDraftMaterialUsage(
    materialId: json['materialId'] as String? ?? '',
    name: json['name'] as String? ?? '',
    quantity: asDoubleOr0(json['quantity']),
    state: _parseResolutionState(json['state'] as String?),
  );
}

class AiDraftControlAnswer {
  const AiDraftControlAnswer({
    required this.ticketControlId,
    this.stringValue,
    this.boolValue,
    this.numberValue,
    required this.state,
  });

  final String ticketControlId;
  final String? stringValue;
  final bool? boolValue;
  final double? numberValue;
  final AiResolutionState state;

  factory AiDraftControlAnswer.fromJson(Map<String, dynamic> json) => AiDraftControlAnswer(
    ticketControlId: json['ticketControlId'] as String? ?? '',
    stringValue: json['stringValue'] as String?,
    boolValue: json['boolValue'] as bool?,
    numberValue: asDouble(json['numberValue']),
    state: _parseResolutionState(json['state'] as String?),
  );

  /// A short human-readable answer, for a one-line list row.
  String describe() {
    if (stringValue != null) return stringValue!;
    if (boolValue != null) return boolValue! ? 'Sì' : 'No';
    if (numberValue != null) return numberValue!.toString();
    return '—';
  }
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
    required this.openItems,
  });

  final String? diagnosi;
  final String? soluzione;
  final String? customerSignoffText;
  final List<AiDraftWorkerRef> workers;
  final List<AiDraftMaterialUsage> materials;
  final List<AiDraftControlAnswer> controlli;
  final List<AiCandidateFact> openItems;

  static const empty = AiCopilotDraftDto(
    workers: [],
    materials: [],
    controlli: [],
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

class AiConversationConfirmResult {
  const AiConversationConfirmResult({required this.reportId, required this.replayed});

  final String reportId;
  final bool replayed;

  factory AiConversationConfirmResult.fromJson(Map<String, dynamic> json) =>
      AiConversationConfirmResult(
        reportId: json['reportId'] as String? ?? '',
        replayed: json['replayed'] as bool? ?? false,
      );
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
      if (data == null)
        throw const AiFailure('Risposta vuota dal servizio AI.');
      return AiReportDraftDto.fromJson(data);
    } on DioException catch (e) {
      throw _translate(e);
    }
  }

  // ── AI Copilot conversation (POST /api/ai/conversations/...) ──────────────────
  //
  // Multi-turn counterpart to [generateDraft] above — the model calls TaskTap tools to verify
  // people/hours/materials/checklist items against real data across several turns instead of one
  // shot. Text-only here: ADR-0017's on-device speech-to-text is not yet wired on this platform
  // (no mic package, no permission declared — see this file's own "Transcription is deliberately
  // absent" note), so there is no voice input to offer on this screen either, same reasoning.

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

  /// POST /api/ai/conversations/{id}/confirm — creates the Bozza from the resolved draft.
  /// [idempotencyKey] should be a fresh id per confirm *attempt* (retried unchanged on a plain
  /// retry, regenerated by the caller after a 409 — mirrors the backend's own reuse contract,
  /// documented on `AiConversationsController.Confirm`).
  Future<AiConversationConfirmResult> confirmConversation(
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
      return AiConversationConfirmResult.fromJson(data);
    } on DioException catch (e) {
      throw _translateConversation(e);
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
      return AiConversationException(
        status,
        'La bozza è cambiata da quando hai provato a confermare — riprova.',
      );
    }

    if (status == 400) {
      final reason = body is String ? body : (map?['error'] as String?);
      return AiConversationException(
        status,
        reason ?? 'Richiesta non valida.',
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
