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

  factory AiReportDraftDto.fromJson(Map<String, dynamic> json) => AiReportDraftDto(
    title: json['title'] as String? ?? '',
    details: json['details'] as String? ?? '',
    modelUsed: json['modelUsed'] as String? ?? '',
    technicianNotes: json['technicianNotes'] as String?,
    suggestedStartedAt: DateTime.tryParse(json['suggestedStartedAt'] as String? ?? '')?.toUtc(),
    suggestedEndedAt: DateTime.tryParse(json['suggestedEndedAt'] as String? ?? '')?.toUtc(),
  );
}

/// The company's monthly allowance is gone. Carries the reset date so the screen can say when it
/// comes back rather than just refusing.
class AiQuotaExhaustedException implements Exception {
  const AiQuotaExhaustedException({this.monthlyLimit, this.used, this.resetsAt});

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
  /// [scheduleId] is required by the contract: the server pulls the intervento's context from the
  /// schedule, and without one there is nothing to draft from.
  Future<AiReportDraftDto> generateDraft({
    required String scheduleId,
    String? ticketId,
    String? voiceTranscript,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/ai/reports/draft',
        data: {
          'scheduleId': scheduleId,
          'ticketId': ?ticketId,
          'voiceTranscript': ?voiceTranscript,
        },
      );
      final data = response.data;
      if (data == null) throw const AiFailure('Risposta vuota dal servizio AI.');
      return AiReportDraftDto.fromJson(data);
    } on DioException catch (e) {
      throw _translate(e);
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

    return const AiFailure('Il servizio AI non ha risposto. Riprova più tardi.');
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
