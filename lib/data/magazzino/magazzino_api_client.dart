import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dio_client.dart';
import '../api/json_parse.dart';

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
    quantita: asDoubleOr0(json['quantita']),
    sottoScorta: json['sottoScorta'] as bool? ?? false,
    magazzinoNome: json['magazzinoNome'] as String?,
    magazzinoTipo: json['magazzinoTipo'] as String?,
    materialeNome: json['materialeNome'] as String?,
    unitOfMeasure: json['unitOfMeasure'] as String?,
    stockMinimo: asDouble(json['stockMinimo']),
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
    data:
        DateTime.tryParse(json['data'] as String? ?? '')?.toUtc() ??
        DateTime.now().toUtc(),
    tipo: json['tipo'] as String? ?? '',
    materialeId: json['materialeId'] as String? ?? '',
    quantita: asDoubleOr0(json['quantita']),
    userId: json['userId'] as String? ?? '',
    magazzinoOrigineNome: json['magazzinoOrigineNome'] as String?,
    magazzinoDestinazioneNome: json['magazzinoDestinazioneNome'] as String?,
    materialeNome: json['materialeNome'] as String?,
    causale: json['causale'] as String?,
    userNome: json['userNome'] as String?,
  );
}

/// A warehouse (Sede or Furgone). Mirrors the `Magazzino` entity — this DTO is only ever built
/// from a raw entity response (`MagazzinoController` returns the entity directly, not a
/// projection), so every field here must tolerate whatever that serializes.
class MagazzinoDto {
  const MagazzinoDto({
    required this.id,
    required this.nome,
    required this.tipo,
    this.assegnatoUserId,
    this.indirizzo,
    this.note,
    required this.isActive,
  });

  final String id;
  final String nome;

  /// `"Sede"` or `"Furgone"` — `MagazzinoTipoEnum` carries its own
  /// `[JsonConverter(typeof(JsonStringEnumConverter))]`, so this is always the string label, never
  /// the numeric value.
  final String tipo;

  /// For a Furgone: the technician it is assigned to. Null for a Sede.
  final String? assegnatoUserId;
  final String? indirizzo;
  final String? note;
  final bool isActive;

  bool get isFurgone => tipo == 'Furgone';

  factory MagazzinoDto.fromJson(Map<String, dynamic> json) => MagazzinoDto(
    id: json['id'] as String? ?? '',
    nome: json['nome'] as String? ?? '',
    tipo: json['tipo'] as String? ?? 'Sede',
    assegnatoUserId: json['assegnatoUserId'] as String?,
    indirizzo: json['indirizzo'] as String?,
    note: json['note'] as String?,
    isActive: json['isActive'] as bool? ?? true,
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

  factory PagedResult.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) item,
  ) => PagedResult(
    elementi: (json['elementi'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .map(item)
        .toList(),
    pagina: asIntOr0(json['pagina']),
    dimensionePagina: asIntOr0(json['dimensionePagina']),
    totaleElementi: asIntOr0(json['totaleElementi']),
    totalePagine: asIntOr0(json['totalePagine']),
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

  // ── Warehouses (Magazzino CRUD) ─────────────────────────────────────────────

  /// GET /api/magazzino
  Future<List<MagazzinoDto>> getMagazzini({
    bool? isActive,
    String? tipo,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/magazzino',
      queryParameters: {'isActive': ?isActive, 'tipo': ?tipo, 'pageSize': 200},
    );
    return pagedItems(
      response.data,
    ).map(MagazzinoDto.fromJson).toList(growable: false);
  }

  /// GET /api/magazzino/furgone/{userId}
  ///
  /// A technician's assigned van warehouse — the default source for rapportino material lines
  /// (`step_materiali_fold.dart`). Returns null when this user has no furgone assigned (a 404 from
  /// the backend, not an error worth surfacing — an office-only technician legitimately has none).
  Future<MagazzinoDto?> getFurgoneByUser(String userId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/magazzino/furgone/$userId',
      );
      final data = response.data;
      return data == null ? null : MagazzinoDto.fromJson(data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  /// POST /api/magazzino
  Future<String> createMagazzino({
    required String nome,
    required String tipo,
    String? assegnatoUserId,
    String? indirizzo,
    String? note,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/magazzino',
      data: {
        'nome': nome,
        'tipo': tipo,
        'assegnatoUserId': ?assegnatoUserId,
        if (indirizzo != null && indirizzo.isNotEmpty) 'indirizzo': indirizzo,
        if (note != null && note.isNotEmpty) 'note': note,
      },
    );
    return response.data!['id'] as String;
  }

  /// PUT /api/magazzino/{id}
  Future<void> updateMagazzino(
    String id, {
    String? nome,
    String? assegnatoUserId,
    String? indirizzo,
    String? note,
    bool? isActive,
  }) async {
    await _dio.put(
      '/api/magazzino/$id',
      data: {
        'nome': ?nome,
        'assegnatoUserId': ?assegnatoUserId,
        'indirizzo': ?indirizzo,
        'note': ?note,
        'isActive': ?isActive,
      },
    );
  }

  // ── Stock movements (write) ──────────────────────────────────────────────────

  /// POST /api/magazzino/{id}/carico — loads stock into a warehouse.
  Future<void> carico({
    required String magazzinoId,
    required String materialeId,
    required double quantita,
    String? note,
  }) async {
    await _dio.post(
      '/api/magazzino/$magazzinoId/carico',
      data: {
        'materialeId': materialeId,
        'quantita': quantita,
        if (note != null && note.isNotEmpty) 'note': note,
      },
    );
  }

  /// POST /api/magazzino/{id}/scarico — unloads stock from a warehouse.
  ///
  /// Throws [DioException] with a 400 response carrying the server's own explanation as a plain
  /// JSON string body when there isn't enough stock — the caller must surface that text rather
  /// than swallow it (`InsufficientStockException` on the backend).
  Future<void> scarico({
    required String magazzinoId,
    required String materialeId,
    required double quantita,
    String? note,
  }) async {
    await _dio.post(
      '/api/magazzino/$magazzinoId/scarico',
      data: {
        'materialeId': materialeId,
        'quantita': quantita,
        if (note != null && note.isNotEmpty) 'note': note,
      },
    );
  }

  /// POST /api/magazzino/{id}/trasferimento — moves stock from [magazzinoId] to
  /// [magazzinoDestinazioneId] atomically. Same insufficient-stock failure mode as [scarico].
  Future<void> trasferimento({
    required String magazzinoId,
    required String materialeId,
    required double quantita,
    required String magazzinoDestinazioneId,
    String? note,
  }) async {
    await _dio.post(
      '/api/magazzino/$magazzinoId/trasferimento',
      data: {
        'materialeId': materialeId,
        'quantita': quantita,
        'magazzinoDestinazioneId': magazzinoDestinazioneId,
        if (note != null && note.isNotEmpty) 'note': note,
      },
    );
  }

  /// PUT /api/magazzino/stock/{id}/stock-minimo — [id] is the stock row's own id (a [GiacenzaDto.id]),
  /// not the warehouse id.
  Future<void> setStockMinimo({
    required String stockId,
    required double stockMinimo,
  }) async {
    await _dio.put(
      '/api/magazzino/stock/$stockId/stock-minimo',
      data: {'stockMinimo': stockMinimo},
    );
  }

  /// DELETE /api/magazzino/stock/{id}/stock-minimo
  Future<void> clearStockMinimo({required String stockId}) async {
    await _dio.delete('/api/magazzino/stock/$stockId/stock-minimo');
  }
}

final magazzinoApiClientProvider = Provider<MagazzinoApiClient>((ref) {
  return MagazzinoApiClient(ref.watch(dioProvider));
});
