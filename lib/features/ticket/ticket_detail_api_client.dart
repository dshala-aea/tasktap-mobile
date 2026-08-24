// dart format width=100
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/dio_client.dart';

/// `TicketsController.UploadAttachment`'s own cap. Checked client-side too — before a photo/file
/// is even queued or sent — so an oversized file is rejected with a clear, actionable sentence
/// rather than a 400 the technician has to make sense of after the upload appears to have run.
const int kMaxTicketAttachmentBytes = 10 * 1024 * 1024;

// ══════════════════════════════════════════════════════════════════════════════
// TicketDetailApiClient
//
// Thin Dio wrapper for the ticket-detail tabs that have no local Drift mirror
// (rapportini, checklist, attachments, fabbisogno — none of these are ever
// written by SyncService). Every call here is fetch-on-demand: nothing is
// cached, so the offline case has to be surfaced as its own outcome
// (TicketDetailOfflineException) rather than folded into a plain empty list
// — see ticket_providers.dart for where that check happens.
// ══════════════════════════════════════════════════════════════════════════════

class TicketDetailApiClient {
  TicketDetailApiClient(this._dio);

  final Dio _dio;

  /// Rapportini recorded against this ticket.
  Future<List<TicketReportSummary>> fetchReportsForTicket(String ticketId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/Reports',
      queryParameters: {'ticketId': ticketId, 'pageSize': 100},
    );
    final items = (response.data?['items'] as List<dynamic>?) ?? const [];
    return items.cast<Map<String, dynamic>>().map(TicketReportSummary.fromJson).toList();
  }

  /// Files uploaded directly to the ticket (not via a rapportino).
  Future<List<TicketAttachmentDto>> fetchAttachments(String ticketId) async {
    final response = await _dio.get<List<dynamic>>('/api/Tickets/$ticketId/attachments');
    return (response.data ?? const [])
        .cast<Map<String, dynamic>>()
        .map(TicketAttachmentDto.fromJson)
        .toList();
  }

  /// The ticket's checklist, resolved from the maintenance-template version it
  /// materialised at creation (ADR-0012). An empty list means no version
  /// resolved — a legitimate state, not a loading failure.
  Future<List<TicketControlGroupDto>> fetchControls(String ticketId) async {
    final response = await _dio.get<List<dynamic>>('/api/tickets/$ticketId/controls');
    return (response.data ?? const [])
        .cast<Map<String, dynamic>>()
        .map(TicketControlGroupDto.fromJson)
        .toList();
  }

  /// Materials planned for the ticket (fabbisogno) — catalogue-backed or free-text.
  Future<List<TicketMaterialeDto>> fetchMateriali(String ticketId) async {
    final response = await _dio.get<List<dynamic>>('/api/Tickets/$ticketId/materiali');
    return (response.data ?? const [])
        .cast<Map<String, dynamic>>()
        .map(TicketMaterialeDto.fromJson)
        .toList();
  }

  /// Uploads one photo/file directly to a ticket (Allegati tab).
  ///
  /// [ticketId] — the ticket to attach it to. [localPath] — absolute path to the local file.
  /// [fileName] — original file name. [contentType] — MIME type (e.g. "image/jpeg").
  ///
  /// The 10 MB cap is enforced by `TicketsController.UploadAttachment` — see
  /// [kMaxTicketAttachmentBytes] for the client-side check that runs before this is ever called.
  ///
  /// Throws [DioException] on network/server error.
  Future<TicketAttachmentUploadResponse> uploadAttachment({
    required String ticketId,
    required String localPath,
    required String fileName,
    required String contentType,
  }) async {
    final file = File(localPath);
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        file.path,
        filename: fileName,
        contentType: DioMediaType.parse(contentType),
      ),
    });

    final response = await _dio.post<Map<String, dynamic>>(
      '/api/tickets/$ticketId/attachments',
      data: formData,
      options: Options(headers: {'Content-Type': 'multipart/form-data'}),
    );

    final data = response.data;
    if (data == null) {
      throw StateError('Empty response from attachment upload');
    }
    return TicketAttachmentUploadResponse.fromJson(data);
  }
}

final ticketDetailApiClientProvider = Provider<TicketDetailApiClient>((ref) {
  return TicketDetailApiClient(ref.watch(dioProvider));
});

// ══════════════════════════════════════════════════════════════════════════════
// Offline signal
// ══════════════════════════════════════════════════════════════════════════════

/// Thrown by the ticket-detail fetch providers when the device is offline —
/// before any request is attempted — so callers can show "non disponibile
/// offline" instead of a generic error. Distinct from a DioException, which
/// means the device WAS online but the request itself failed.
class TicketDetailOfflineException implements Exception {
  const TicketDetailOfflineException();

  @override
  String toString() => 'Offline: dati non disponibili senza connessione.';
}

// ══════════════════════════════════════════════════════════════════════════════
// DTOs
// ══════════════════════════════════════════════════════════════════════════════

double? _asDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

/// One rapportino recorded against a ticket (Report tab).
class TicketReportSummary {
  const TicketReportSummary({
    required this.id,
    required this.title,
    required this.stato,
    required this.createdAt,
  });

  final String id;
  final String title;

  /// Raw ReportStatoEnum ordinal (0=Bozza … 5=Annullato) — the backend
  /// serializes it as an int, not the string StatusPill expects.
  final int stato;
  final DateTime createdAt;

  static const _statoLabels = {
    0: 'Bozza',
    1: 'Inviato',
    2: 'Controllato',
    3: 'Fatturato',
    4: 'Respinto',
    5: 'Annullato',
  };

  String get statoLabel => _statoLabels[stato] ?? 'Bozza';

  factory TicketReportSummary.fromJson(Map<String, dynamic> json) {
    return TicketReportSummary(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      stato: json['stato'] as int? ?? 0,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// One file attached directly to the ticket (Allegati tab).
class TicketAttachmentDto {
  const TicketAttachmentDto({
    required this.id,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
    required this.contentUrl,
    required this.createdAt,
  });

  final String id;
  final String fileName;
  final String contentType;
  final int sizeBytes;
  final String contentUrl;
  final DateTime createdAt;

  factory TicketAttachmentDto.fromJson(Map<String, dynamic> json) {
    return TicketAttachmentDto(
      id: json['id'] as String,
      fileName: json['fileName'] as String? ?? '',
      contentType: json['contentType'] as String? ?? '',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      contentUrl: json['contentUrl'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// Response from `POST /api/tickets/{id}/attachments` — just enough to mark the local outbox
/// row submitted. The full [TicketAttachmentDto] (fileName/size/createdAt/…) comes back from the
/// next `GET /api/Tickets/{id}/attachments` instead, which is what the Allegati tab re-fetches
/// after an upload lands.
class TicketAttachmentUploadResponse {
  const TicketAttachmentUploadResponse({required this.allegatoId, required this.contentUrl});

  final String allegatoId;
  final String contentUrl;

  factory TicketAttachmentUploadResponse.fromJson(Map<String, dynamic> json) {
    return TicketAttachmentUploadResponse(
      allegatoId: json['allegatoId'] as String,
      contentUrl: json['contentUrl'] as String? ?? '',
    );
  }
}

/// One planned material on a ticket (Fabbisogno tab) — catalogue-backed or free text.
class TicketMaterialeDto {
  const TicketMaterialeDto({
    required this.id,
    this.materialeId,
    this.codice,
    required this.nome,
    required this.quantita,
    this.unitaMisura,
    this.note,
    required this.disponibile,
  });

  final String id;
  final String? materialeId;
  final String? codice;
  final String nome;
  final double quantita;
  final String? unitaMisura;
  final String? note;
  final bool disponibile;

  factory TicketMaterialeDto.fromJson(Map<String, dynamic> json) {
    return TicketMaterialeDto(
      id: json['id'] as String,
      materialeId: json['materialeId'] as String?,
      codice: json['codice'] as String?,
      nome: json['nome'] as String? ?? '',
      quantita: _asDouble(json['quantita']) ?? 0,
      unitaMisura: json['unitaMisura'] as String?,
      note: json['note'] as String?,
      disponibile: json['disponibile'] as bool? ?? true,
    );
  }
}

/// How a control renders its input and stores its value — mirrors the
/// backend's ControlTypeEnum (serialized as a plain int, no string converter).
enum ControlType { checkbox, freeText, radioOnOff, date, singleChoice, unknown }

ControlType _controlTypeFromInt(int? value) {
  return switch (value) {
    0 => ControlType.checkbox,
    1 => ControlType.freeText,
    2 => ControlType.radioOnOff,
    3 => ControlType.date,
    4 => ControlType.singleChoice,
    _ => ControlType.unknown,
  };
}

/// A section of the ticket's checklist (Controllo tab / rapportino checklist).
class TicketControlGroupDto {
  const TicketControlGroupDto({
    required this.id,
    required this.name,
    this.description,
    required this.sortOrder,
    this.subgroups = const [],
    this.controls = const [],
  });

  final String id;
  final String name;
  final String? description;
  final int sortOrder;
  final List<TicketControlGroupDto> subgroups;
  final List<TicketControlDto> controls;

  factory TicketControlGroupDto.fromJson(Map<String, dynamic> json) {
    return TicketControlGroupDto(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      sortOrder: json['sortOrder'] as int? ?? 0,
      subgroups: ((json['subgroups'] as List<dynamic>?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(TicketControlGroupDto.fromJson)
          .toList(),
      controls: ((json['controls'] as List<dynamic>?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(TicketControlDto.fromJson)
          .toList(),
    );
  }
}

/// One checklist item: what it asks (from the frozen template) and where it
/// has got to on this ticket. `id` is the TicketControl id — the identity a
/// rapportino's finding references (SubmitReportControlloDto.controlId).
class TicketControlDto {
  const TicketControlDto({
    required this.id,
    required this.templateControlId,
    required this.label,
    this.description,
    required this.type,
    required this.isRequired,
    this.options,
    this.valoreLimite,
    required this.sortOrder,
    required this.status,
    this.stringValue,
    this.boolValue,
    this.dateValue,
  });

  final String id;
  final String templateControlId;
  final String label;
  final String? description;
  final ControlType type;
  final bool isRequired;

  /// Serialized choice list (JSON array of strings) for [ControlType.singleChoice].
  final String? options;
  final double? valoreLimite;
  final int sortOrder;

  /// TicketControlStatus as a string: Pending | Completed | NotApplicable.
  final String status;

  /// The current answer, in the column matching [type].
  final String? stringValue;
  final bool? boolValue;
  final DateTime? dateValue;

  /// [options] parsed as a choice list, or empty when absent/unparseable.
  List<String> get choiceOptions {
    final raw = options;
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {
      // Not valid JSON — no choices to offer.
    }
    return const [];
  }

  factory TicketControlDto.fromJson(Map<String, dynamic> json) {
    return TicketControlDto(
      id: json['id'] as String,
      templateControlId: json['templateControlId'] as String? ?? '',
      label: json['label'] as String? ?? '',
      description: json['description'] as String?,
      type: _controlTypeFromInt(json['type'] as int?),
      isRequired: json['isRequired'] as bool? ?? false,
      options: json['options'] as String?,
      valoreLimite: _asDouble(json['valoreLimite']),
      sortOrder: json['sortOrder'] as int? ?? 0,
      status: json['status'] as String? ?? 'Pending',
      stringValue: json['stringValue'] as String?,
      boolValue: json['boolValue'] as bool?,
      dateValue: json['dateValue'] != null ? DateTime.tryParse(json['dateValue'] as String) : null,
    );
  }
}

/// One checklist item flattened out of the group tree, with its group path
/// ("Sezione › Sotto-sezione") kept for display context.
class FlatTicketControl {
  const FlatTicketControl({required this.groupPath, required this.control});

  final String groupPath;
  final TicketControlDto control;
}

/// Depth-first flatten of a checklist tree, preserving the backend's
/// ordering (groups by sortOrder/name, controls within a group by
/// sortOrder/label).
List<FlatTicketControl> flattenTicketControls(
  List<TicketControlGroupDto> groups, [
  String pathPrefix = '',
]) {
  final result = <FlatTicketControl>[];
  for (final group in groups) {
    final path = pathPrefix.isEmpty ? group.name : '$pathPrefix › ${group.name}';
    for (final control in group.controls) {
      result.add(FlatTicketControl(groupPath: path, control: control));
    }
    result.addAll(flattenTicketControls(group.subgroups, path));
  }
  return result;
}
