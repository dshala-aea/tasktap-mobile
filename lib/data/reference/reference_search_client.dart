// dart format width=100
import 'package:dio/dio.dart';

import '../api/json_parse.dart';
import '../sync/sync_dto.dart';
import 'reference_cache_repository.dart';
import 'reference_option.dart';

/// Search the server for a reference row and write what comes back into the mirror *before*
/// returning it. The technician's own successful query is the authorisation for the write; see the
/// plan's Global Constraints on why this is not a violation of D-1(a).
///
/// Offline this returns an empty list rather than throwing: the picker falls back to the local
/// mirror, which is the offline answer anyway. A search that fails is not an error the technician
/// can act on. Catches `Object`, not `DioException` — a timeout, a 4xx, a 503 and a parse failure all
/// belong on the same fallback path, and `dioProvider` installs no error mapper that would turn them
/// into one type.
///
/// Takes a bare [Dio], like every other client in `lib/data/**`: there is no shared `ApiClient` in
/// this repo.
///
/// Every method is the same three moves — ask, upsert, return — and the middle one is the reason
/// this class exists rather than the widget calling Dio directly: a row a technician can *see* is a
/// row the mirror already has, so the ticket written from that pick cannot reference a missing row.
class ReferenceSearchClient {
  ReferenceSearchClient(this._dio, this._cache);

  final Dio _dio;
  final ReferenceCacheRepository _cache;

  /// One screenful. The server clamps this to [1,100] and the picker shows six, so a larger page
  /// would only be paid for over a technician's mobile connection and never read.
  static const int _pageSize = 20;

  Future<List<ReferenceOption>> searchContracts({
    required String customerId,
    required String query,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/contracts',
        queryParameters: {
          // Scope, always. A search widens *discovery*, never the security boundary.
          'customerId': customerId,
          'isActive': 'true',
          'q': query,
          'pageSize': _pageSize,
        },
      );
      final rows = pagedItems(response.data).map(ContractSyncDto.fromJson).toList();
      await _cache.upsertContracts(rows);
      return rows.map(ReferenceOption.contract).toList();
    } on Object {
      return const [];
    }
  }

  Future<List<ReferenceOption>> searchCommesse({
    required String customerId,
    required String query,
  }) async {
    try {
      // No `stato` filter, deliberately: the mirror's `commesseForCustomer` filters on nothing but
      // `isActive`, and a search that returned a different set from the one the device holds would
      // make the picker's two halves disagree for no reason a technician could see.
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/commesse',
        queryParameters: {
          'customerId': customerId,
          'isActive': 'true',
          'q': query,
          'pageSize': _pageSize,
        },
      );
      final rows = pagedItems(response.data).map(CommessaSyncDto.fromJson).toList();
      await _cache.upsertCommesse(rows);
      return rows.map(ReferenceOption.commessa).toList();
    } on Object {
      return const [];
    }
  }

  Future<List<ReferenceOption>> searchProdottiAssistenza({
    required String customerId,
    required String query,
  }) async {
    try {
      // Singular: `ProdottoAssistenzaController` is `[Route("api/[controller]")]`, so the path is the
      // controller name with the singular "Prodotto" in it. A plural here 404s, which is a silent
      // fallback to the mirror — the picker would look like it searched and found nothing new.
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/prodottoassistenza',
        queryParameters: {
          'customerId': customerId,
          'isActive': 'true',
          'q': query,
          'pageSize': _pageSize,
        },
      );
      final rows = pagedItems(response.data).map(ProdottoAssistenzaSyncDto.fromJson).toList();
      await _cache.upsertProdottiAssistenza(rows);
      return rows.map(ReferenceOption.prodotto).toList();
    } on Object {
      return const [];
    }
  }

  /// No customer scope: an agent is not a customer's list, it is the tenant's — the customerId
  /// parameter this endpoint does not take is exactly right.
  ///
  /// `GET /api/agents` is gated by `ClientiAgentRead`, which a technician may not hold — in which
  /// case this 403s and returns empty, and the picker shows the mirrored agents, which came from
  /// the technician's own tickets and need no permission. That is the designed behaviour, not a
  /// failure to report.
  Future<List<ReferenceOption>> searchAgents({required String query}) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/agents',
        queryParameters: {'isActive': 'true', 'q': query, 'pageSize': _pageSize},
      );
      final rows = pagedItems(response.data).map(AgentSyncDto.fromJson).toList();
      await _cache.upsertAgents(rows);
      return rows.map(ReferenceOption.agent).toList();
    } on Object {
      return const [];
    }
  }
}
