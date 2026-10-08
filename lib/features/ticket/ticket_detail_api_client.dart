// dart format width=100
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/dio_client.dart';
import '../../data/api/json_parse.dart';
import '../../domain/checklist/control_type.dart';
export '../../domain/checklist/control_type.dart';

/// `TicketsController.UploadAttachment`'s own cap. Checked client-side too — before a photo/file
/// is even queued or sent — so an oversized file is rejected with a clear, actionable sentence
/// rather than a 400 the technician has to make sense of after the upload appears to have run.
const int kMaxTicketAttachmentBytes = 10 * 1024 * 1024;

// ══════════════════════════════════════════════════════════════════════════════
// TicketDetailApiClient
//
// Thin Dio wrapper for the ticket-detail tabs. Most of these (rapportini, checklist,
// attachments) have no local Drift mirror — every call is fetch-on-demand, so the offline case
// has to be surfaced as its own outcome (TicketDetailOfflineException) rather than folded into a
// plain empty list, see ticket_providers.dart for where that check happens. Fabbisogno is the one
// exception: it IS local-Drift-backed (see ticketMaterialiProvider's own doc comment), so
// fetchMateriali here isn't the tab's read path — it exists purely for setMateriali's own
// post-write refresh (see that method's doc comment).
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

  /// The ticket's full checklist response: ticket-level `groups`, legacy `assetProgress` and the
  /// templated `assetChecklists` (hand-off section 2). [fetchControls] below keeps the old
  /// groups-only contract for the screens that only know the ticket level.
  Future<TicketControlResponseDto> fetchControlsResponse(String ticketId) async {
    final response = await _dio.get<Map<String, dynamic>>('/api/tickets/$ticketId/controls');
    return TicketControlResponseDto.fromJson(response.data ?? const {});
  }

  /// The ticket's checklist groups, resolved from the maintenance-template version it
  /// materialised at creation (ADR-0012). An empty list means no version
  /// resolved — a legitimate state, not a loading failure.
  ///
  /// The groups-only read of [fetchControlsResponse], kept for the screens that only know the
  /// ticket level (`assetProgress`/`assetChecklists` are dropped here; use
  /// [fetchControlsResponse] to get them).
  Future<List<TicketControlGroupDto>> fetchControls(String ticketId) async =>
      (await fetchControlsResponse(ticketId)).groups;

  /// Materials planned for the ticket (fabbisogno) — catalogue-backed or free-text.
  Future<List<TicketMaterialeDto>> fetchMateriali(String ticketId) async {
    final response = await _dio.get<List<dynamic>>('/api/Tickets/$ticketId/materiali');
    return (response.data ?? const [])
        .cast<Map<String, dynamic>>()
        .map(TicketMaterialeDto.fromJson)
        .toList();
  }

  /// Replaces a ticket's planned materials (fabbisogno) wholesale — mirrors
  /// `TicketsController.SetMateriali`, which deletes every existing row and inserts the submitted
  /// list fresh. No per-row server id to reconcile against (same reasoning that endpoint's own
  /// doc comment gives), which is why this takes the full replacement list, not a diff.
  Future<void> setMateriali(String ticketId, List<TicketMaterialeWriteRow> rows) async {
    await _dio.put<dynamic>(
      '/api/Tickets/$ticketId/materiali',
      data: rows.map((r) => r.toJson()).toList(),
    );
  }

  /// Tenant-wide catalogue article search (not stock/warehouse-scoped, unlike
  /// MagazzinoApiClient's van-inventory methods) — the picker half of the Fabbisogno editor's
  /// "catalogue article OR free text" row choice. Tolerates either an `{items: [...]}` envelope
  /// or a bare array (see [pagedItems]) since the exact shape wasn't pinned down before this.
  Future<List<MaterialeSearchResult>> searchMateriali(String query) async {
    final response = await _dio.get<dynamic>(
      '/Materiali',
      queryParameters: {'q': query, 'page': 1, 'pageSize': 20},
    );
    return pagedItems(response.data).map(MaterialeSearchResult.fromJson).toList();
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

  /// ReportStatoEnum ordinal (0=Bozza … 6=NonFatturabile), normalized from whichever shape the
  /// backend sends: `GET /api/Reports` serializes the real `Report` entity, and `Report.Stato`
  /// carries `[JsonConverter(JsonStringEnumConverter)]` (added for the mobile sync payload — see
  /// that property's own doc comment), so this arrives as the enum's NAME ("Inviato"), not its
  /// ordinal — unlike other endpoints whose hand-rolled anonymous projections don't inherit that
  /// attribute and still send a raw int. Tolerate both rather than assume one.
  final int stato;
  final DateTime createdAt;

  static const _statoLabels = {
    0: 'Bozza',
    1: 'Inviato',
    2: 'Controllato',
    3: 'Fatturato',
    4: 'Respinto',
    5: 'Annullato',
    6: 'NonFatturabile',
  };

  static const _statoOrdinals = {
    'Bozza': 0,
    'Inviato': 1,
    'Controllato': 2,
    'Fatturato': 3,
    'Respinto': 4,
    'Annullato': 5,
    'NonFatturabile': 6,
  };

  static int _parseStato(dynamic raw) {
    if (raw is int) return raw;
    if (raw is String) return _statoOrdinals[raw] ?? 0;
    return 0;
  }

  String get statoLabel => _statoLabels[stato] ?? 'Bozza';

  factory TicketReportSummary.fromJson(Map<String, dynamic> json) {
    return TicketReportSummary(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      stato: _parseStato(json['stato']),
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

/// One row the Fabbisogno editor submits to [TicketDetailApiClient.setMateriali] — mirrors
/// `CreateTicketMaterialeRequest`'s shape exactly (`materialeId`/`freeTextName` mutually
/// exclusive, `quantity` required, `unitOfMeasure`/`notes` optional).
class TicketMaterialeWriteRow {
  const TicketMaterialeWriteRow({
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

  Map<String, dynamic> toJson() => {
    'materialeId': materialeId,
    'freeTextName': freeTextName,
    'quantity': quantity,
    'unitOfMeasure': unitOfMeasure,
    'notes': notes,
  };
}

/// One catalogue article from [TicketDetailApiClient.searchMateriali].
class MaterialeSearchResult {
  const MaterialeSearchResult({
    required this.id,
    required this.name,
    this.code,
    this.unitOfMeasure,
  });

  final String id;
  final String name;
  final String? code;
  final String? unitOfMeasure;

  factory MaterialeSearchResult.fromJson(Map<String, dynamic> json) {
    return MaterialeSearchResult(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      code: json['code'] as String?,
      unitOfMeasure: json['unitOfMeasure'] as String?,
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
    this.numberValue,
    this.controlLineageId = '',
    this.note,
    this.prodottoAssistenzaId,
  });

  final String id;
  final String templateControlId;
  final String label;
  final String? description;
  final ControlType type;
  final bool isRequired;

  /// Serialized choice list (JSON array of strings) for [ControlType.options].
  final String? options;
  final double? valoreLimite;
  final int sortOrder;

  /// TicketControlStatus as a string: Pending | Completed | NotApplicable.
  final String status;

  /// The current answer, in the column matching [type].
  final String? stringValue;
  final bool? boolValue;
  final DateTime? dateValue;
  final double? numberValue;

  /// Version-independent control identity (bulk selector, cross-asset matching). Empty only for a
  /// payload from a server that predates it.
  final String controlLineageId;

  /// Remark stored with the answer; a note never counts as an answer.
  final String? note;

  /// Null for a ticket-level row.
  final String? prodottoAssistenzaId;

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
      type: controlTypeFromWire(json['type'] as String?),
      isRequired: json['isRequired'] as bool? ?? false,
      options: json['options'] as String?,
      valoreLimite: _asDouble(json['valoreLimite']),
      sortOrder: json['sortOrder'] as int? ?? 0,
      status: json['status'] as String? ?? 'Pending',
      stringValue: json['stringValue'] as String?,
      boolValue: json['boolValue'] as bool?,
      dateValue: json['dateValue'] != null ? DateTime.tryParse(json['dateValue'] as String) : null,
      numberValue: _asDouble(json['numberValue']),
      controlLineageId: json['controlLineageId'] as String? ?? '',
      note: json['note'] as String?,
      prodottoAssistenzaId: json['prodottoAssistenzaId'] as String?,
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

/// The legacy per-asset Controllato/Note of `GET /api/tickets/{id}/controls` — an asset that is not
/// templated. Read-only here: updating it is `PUT .../asset-progress`, which is online-only.
class TicketAssetProgressDto {
  const TicketAssetProgressDto({
    required this.prodottoAssistenzaId,
    required this.prodottoAssistenzaName,
    required this.controllato,
    this.note,
  });

  final String prodottoAssistenzaId;
  final String prodottoAssistenzaName;
  final bool controllato;
  final String? note;

  factory TicketAssetProgressDto.fromJson(Map<String, dynamic> j) => TicketAssetProgressDto(
    prodottoAssistenzaId: j['prodottoAssistenzaId'] as String,
    prodottoAssistenzaName: j['prodottoAssistenzaName'] as String? ?? '',
    controllato: j['controllato'] as bool? ?? false,
    note: j['note'] as String?,
  );
}

/// One covered asset's own templated checklist, as `GET /api/tickets/{id}/controls` returns it
/// under `assetChecklists`. Carries the asset identity (matricola, its single libretto) alongside
/// the checklist groups, which the ticket-level `groups` do not.
class TicketAssetChecklistDto {
  const TicketAssetChecklistDto({
    required this.prodottoAssistenzaId,
    required this.name,
    this.matricola,
    this.librettoId,
    this.librettoName,
    required this.maintenanceTemplateVersionId,
    this.groups = const [],
  });

  final String prodottoAssistenzaId;
  final String name;
  final String? matricola;
  final String? librettoId;
  final String? librettoName;
  final String maintenanceTemplateVersionId;
  final List<TicketControlGroupDto> groups;

  factory TicketAssetChecklistDto.fromJson(Map<String, dynamic> j) => TicketAssetChecklistDto(
    prodottoAssistenzaId: j['prodottoAssistenzaId'] as String,
    name: j['name'] as String? ?? '',
    matricola: j['matricola'] as String?,
    librettoId: j['librettoId'] as String?,
    librettoName: j['librettoName'] as String?,
    maintenanceTemplateVersionId: j['maintenanceTemplateVersionId'] as String? ?? '',
    groups: ((j['groups'] as List<dynamic>?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(TicketControlGroupDto.fromJson)
        .toList(),
  );
}

/// The whole `GET /api/tickets/{id}/controls` response: ticket-level `groups`, the legacy
/// `assetProgress` and the templated `assetChecklists`.
class TicketControlResponseDto {
  const TicketControlResponseDto({
    this.groups = const [],
    this.assetProgress = const [],
    this.assetChecklists = const [],
  });

  final List<TicketControlGroupDto> groups;
  final List<TicketAssetProgressDto> assetProgress;
  final List<TicketAssetChecklistDto> assetChecklists;

  factory TicketControlResponseDto.fromJson(Map<String, dynamic> j) => TicketControlResponseDto(
    groups: ((j['groups'] as List<dynamic>?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(TicketControlGroupDto.fromJson)
        .toList(),
    assetProgress: ((j['assetProgress'] as List<dynamic>?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(TicketAssetProgressDto.fromJson)
        .toList(),
    assetChecklists: ((j['assetChecklists'] as List<dynamic>?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(TicketAssetChecklistDto.fromJson)
        .toList(),
  );
}
