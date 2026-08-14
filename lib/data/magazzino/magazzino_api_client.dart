import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dio_client.dart';

/// Stock levels and stock movements, from the `/api/app/*` endpoints built for this client.
///
/// The magazzino screen has shown a materiali *catalogue* — what exists — since sync started
/// filling that mirror. What it never showed is the number a technician on site actually needs:
/// how many are left, and where. `GET /api/app/magazzino/giacenze` has been live the whole time
/// with no call site, which is why `magazzino_screen.dart` carried a
/// `// TODO(backend): warehouses + movements not synced to mobile.` describing a gap that was
/// client-side.
///
/// ## Online-only, deliberately
///
/// Unlike the catalogue, giacenze are not mirrored into Drift. A stock level is the one number in
/// this app that is worthless when stale — telling a technician they have four of something when
/// the count is from Tuesday is worse than telling them the figure is unavailable. So these read
/// straight through, and the screen states plainly when it could not reach the server rather than
/// showing a cached quantity.

/// Numbers arrive as either a JSON number or a string.
///
/// The backend serialises decimals as strings on some paths and as numbers on others (both shapes
/// are declared in the OpenAPI snapshot as `number|string`). Parsing defensively here rather than
/// casting keeps a quantity of `"4.0"` from throwing at the top of a technician's stock list.
double _num(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

int _int(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

/// One material's stock in one warehouse.
class GiacenzaDto {
  const GiacenzaDto({
    required this.id,
    required this.magazzinoId,
    required this.materialeId,
    required this.quantita,
    required this.sottoScorta,
    this.magazzinoNome,
    this.magazzinoTipo,
    this.materialeNome,
    this.unitOfMeasure,
    this.stockMinimo,
  });

  final String id;
  final String magazzinoId;
  final String materialeId;
  final double quantita;

  /// The server's own verdict on whether this is below its minimum.
  ///
  /// Taken from the server rather than recomputed as `quantita < stockMinimo`: the threshold rule
  /// belongs to the backend, `stockMinimo` is nullable, and a client that re-derives it will
  /// eventually disagree with the office web app about which lines are short.
  final bool sottoScorta;

  final String? magazzinoNome;
  final String? magazzinoTipo;
  final String? materialeNome;
  final String? unitOfMeasure;
  final double? stockMinimo;

  factory GiacenzaDto.fromJson(Map<String, dynamic> json) => GiacenzaDto(
    id: json['id'] as String? ?? '',
    magazzinoId: json['magazzinoId'] as String? ?? '',
    materialeId: json['materialeId'] as String? ?? '',
    quantita: _num(json['quantita']),
    sottoScorta: json['sottoScorta'] as bool? ?? false,
    magazzinoNome: json['magazzinoNome'] as String?,
    magazzinoTipo: json['magazzinoTipo'] as String?,
    materialeNome: json['materialeNome'] as String?,
    unitOfMeasure: json['unitOfMeasure'] as String?,
    stockMinimo: json['stockMinimo'] == null ? null : _num(json['stockMinimo']),
  );
}

/// One stock movement: a load, an unload, or a transfer between warehouses.
class MovimentoDto {
  const MovimentoDto({
    required this.id,
    required this.data,
    required this.tipo,
    required this.materialeId,
    required this.quantita,
    required this.userId,
    this.magazzinoOrigineNome,
    this.magazzinoDestinazioneNome,
    this.materialeNome,
    this.causale,
    this.userNome,
  });

  final String id;
  final DateTime data;
  final String tipo;
  final String materialeId;
  final double quantita;
  final String userId;
  final String? magazzinoOrigineNome;
  final String? magazzinoDestinazioneNome;
  final String? materialeNome;
  final String? causale;
  final String? userNome;

  factory MovimentoDto.fromJson(Map<String, dynamic> json) => MovimentoDto(
    id: json['id'] as String? ?? '',
    data: DateTime.tryParse(json['data'] as String? ?? '')?.toUtc() ?? DateTime.now().toUtc(),
    tipo: json['tipo'] as String? ?? '',
    materialeId: json['materialeId'] as String? ?? '',
    quantita: _num(json['quantita']),
    userId: json['userId'] as String? ?? '',
    magazzinoOrigineNome: json['magazzinoOrigineNome'] as String?,
    magazzinoDestinazioneNome: json['magazzinoDestinazioneNome'] as String?,
    materialeNome: json['materialeNome'] as String?,
    causale: json['causale'] as String?,
    userNome: json['userNome'] as String?,
  );
}

/// A page of results, carrying enough to know whether more exist.
class PagedResult<T> {
  const PagedResult({
    required this.elementi,
    required this.pagina,
    required this.dimensionePagina,
    required this.totaleElementi,
    required this.totalePagine,
  });

  final List<T> elementi;
  final int pagina;
  final int dimensionePagina;
  final int totaleElementi;
  final int totalePagine;

  bool get hasMore => pagina < totalePagine;

  factory PagedResult.fromJson(Map<String, dynamic> json, T Function(Map<String, dynamic>) item) =>
      PagedResult(
        elementi: (json['elementi'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>()
            .map(item)
            .toList(),
        pagina: _int(json['pagina']),
        dimensionePagina: _int(json['dimensionePagina']),
        totaleElementi: _int(json['totaleElementi']),
        totalePagine: _int(json['totalePagine']),
      );
}

class MagazzinoApiClient {
  MagazzinoApiClient(this._dio);

  final Dio _dio;

  /// GET /api/app/magazzino/giacenze
  ///
  /// [sottoScorta] true asks the server for only the lines below their minimum — the "what am I
  /// about to run out of" question, answered without pulling the whole warehouse over a field
  /// connection.
  Future<PagedResult<GiacenzaDto>> getGiacenze({
    String? magazzinoId,
    bool? sottoScorta,
    String? q,
    int page = 1,
    int pageSize = 50,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/app/magazzino/giacenze',
      queryParameters: {
        'magazzinoId': ?magazzinoId,
        'sottoScorta': ?sottoScorta,
        if (q != null && q.isNotEmpty) 'q': q,
        'page': page,
        'pageSize': pageSize,
      },
    );

    final data = response.data;
    if (data == null) throw StateError('Risposta vuota da giacenze');
    return PagedResult.fromJson(data, GiacenzaDto.fromJson);
  }

  /// GET /api/app/magazzino/movimenti
  Future<PagedResult<MovimentoDto>> getMovimenti({
    String? tipo,
    String? magazzinoId,
    String? materialeId,
    DateTime? dataFrom,
    DateTime? dataTo,
    String? q,
    int page = 1,
    int pageSize = 50,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/app/magazzino/movimenti',
      queryParameters: {
        'tipo': ?tipo,
        'magazzinoId': ?magazzinoId,
        'materialeId': ?materialeId,
        if (dataFrom != null) 'dataFrom': dataFrom.toUtc().toIso8601String(),
        if (dataTo != null) 'dataTo': dataTo.toUtc().toIso8601String(),
        if (q != null && q.isNotEmpty) 'q': q,
        'page': page,
        'pageSize': pageSize,
      },
    );

    final data = response.data;
    if (data == null) throw StateError('Risposta vuota da movimenti');
    return PagedResult.fromJson(data, MovimentoDto.fromJson);
  }
}

final magazzinoApiClientProvider = Provider<MagazzinoApiClient>((ref) {
  return MagazzinoApiClient(ref.watch(dioProvider));
});
