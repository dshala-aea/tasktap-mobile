import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dio_client.dart';
import '../api/json_parse.dart';

/// The customer record the local mirror does not carry.
///
/// `GET /api/app/clienti/{id}/overview` has been live with no call site. What it adds over the
/// synced `customers` table is not cosmetic: the mirror has no `pec`, no `sdiCode`, no
/// `codiceFiscale` and no `provincia` — the four fields an Italian technician is most likely to be
/// asked for on site — and none of the four counts.
///
/// It is **enrichment, never the base**. The cliente detail screen keeps reading the Drift mirror
/// for everything it already showed, so the screen works exactly as before with no signal; this
/// fills in what the mirror cannot answer and says so plainly when it is unreachable. Replacing
/// the local read with this one would have traded an offline screen for a prettier online one.
class ClienteOverviewDto {
  const ClienteOverviewDto({
    required this.id,
    required this.ragioneSociale,
    required this.attivo,
    required this.sediAttive,
    required this.contratti,
    required this.interventiTotali,
    required this.interventiAperti,
    this.partitaIva,
    this.codiceFiscale,
    this.email,
    this.pec,
    this.sdiCode,
    this.telefono,
    this.indirizzo,
    this.citta,
    this.cap,
    this.provincia,
    this.paese,
    this.contatto,
    this.note,
  });

  final String id;
  final String ragioneSociale;
  final bool attivo;

  final int sediAttive;
  final int contratti;
  final int interventiTotali;
  final int interventiAperti;

  final String? partitaIva;
  final String? codiceFiscale;
  final String? email;

  /// Posta elettronica certificata — legally addressable email. Not in the local mirror.
  final String? pec;

  /// The e-invoicing recipient code. Not in the local mirror.
  final String? sdiCode;

  final String? telefono;
  final String? indirizzo;
  final String? citta;
  final String? cap;
  final String? provincia;
  final String? paese;
  final String? contatto;
  final String? note;

  factory ClienteOverviewDto.fromJson(Map<String, dynamic> json) => ClienteOverviewDto(
    id: json['id'] as String? ?? '',
    ragioneSociale: json['ragioneSociale'] as String? ?? '',
    attivo: json['attivo'] as bool? ?? true,
    sediAttive: asIntOr0(json['sediAttive']),
    contratti: asIntOr0(json['contratti']),
    interventiTotali: asIntOr0(json['interventiTotali']),
    interventiAperti: asIntOr0(json['interventiAperti']),
    partitaIva: json['partitaIva'] as String?,
    codiceFiscale: json['codiceFiscale'] as String?,
    email: json['email'] as String?,
    pec: json['pec'] as String?,
    sdiCode: json['sdiCode'] as String?,
    telefono: json['telefono'] as String?,
    indirizzo: json['indirizzo'] as String?,
    citta: json['citta'] as String?,
    cap: json['cap'] as String?,
    provincia: json['provincia'] as String?,
    paese: json['paese'] as String?,
    contatto: json['contatto'] as String?,
    note: json['note'] as String?,
  );
}

/// Thrown before a request is attempted, so the screen can say "offline" rather than render a
/// generic failure for something that never left the device.
class ClienteOverviewOfflineException implements Exception {
  const ClienteOverviewOfflineException();

  @override
  String toString() => 'Offline: scheda cliente completa non disponibile.';
}

class ClienteOverviewApiClient {
  ClienteOverviewApiClient(this._dio);

  final Dio _dio;

  Future<ClienteOverviewDto> getOverview(String customerId) async {
    final response = await _dio.get<Map<String, dynamic>>('/api/app/clienti/$customerId/overview');
    final data = response.data;
    if (data == null) throw StateError('Risposta vuota da clienti overview');
    return ClienteOverviewDto.fromJson(data);
  }
}

final clienteOverviewApiClientProvider = Provider<ClienteOverviewApiClient>((ref) {
  return ClienteOverviewApiClient(ref.watch(dioProvider));
});
