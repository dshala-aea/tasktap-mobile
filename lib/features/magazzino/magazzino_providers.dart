import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/error_message.dart' show isTransportOrServerFault;
import '../../data/local/app_database.dart';
import '../../data/magazzino/magazzino_api_client.dart';
import '../../data/sync/connectivity_provider.dart';
import '../../data/sync/sync_service.dart';

/// All active materiali, alphabetical by name.
///
/// The materiali catalogue, from the local mirror the sync fills — readable offline.
final materialiCatalogProvider =
    StreamProvider.autoDispose<List<MaterialiData>>((ref) {
      final db = ref.watch(appDatabaseProvider);
      return (db.select(db.materiali)
            ..where((m) => m.isActive.equals(true))
            ..orderBy([(m) => OrderingTerm.asc(m.name)]))
          .watch();
    });

/// Current stock, straight from the server.
///
/// Not a Drift stream like the catalogue above, and not cached. A stock level is the one figure in
/// this app that is actively harmful when stale: a technician who reads "4 in stock" from Tuesday's
/// mirror and drives out without the part has been misled by the app, where "non disponibile
/// offline" would have sent them to the phone instead. So this reads through, and the screen says
/// so when it cannot.
///
/// Autodisposed and family-keyed on the search term so switching filters does not hold a stale
/// page alive behind the new one.
final giacenzeProvider = FutureProvider.autoDispose
    .family<PagedResult<GiacenzaDto>, GiacenzeQuery>((ref, query) async {
      final client = ref.watch(magazzinoApiClientProvider);
      return client.getGiacenze(
        q: query.q,
        sottoScorta: query.soloSottoScorta ? true : null,
        pageSize: query.pageSize,
      );
    });

/// The arguments the giacenze list is keyed on.
///
/// A value type with real equality: a `family` keyed on a plain record or an inline object would
/// re-fetch on every rebuild, which on this screen means a network call per keystroke.
class GiacenzeQuery {
  const GiacenzeQuery({
    this.q,
    this.soloSottoScorta = false,
    this.pageSize = 50,
  });

  final String? q;
  final bool soloSottoScorta;
  final int pageSize;

  @override
  bool operator ==(Object other) =>
      other is GiacenzeQuery &&
      other.q == q &&
      other.soloSottoScorta == soloSottoScorta &&
      other.pageSize == pageSize;

  @override
  int get hashCode => Object.hash(q, soloSottoScorta, pageSize);
}

/// Recent stock movements, most recent first. Same online-only reasoning as [giacenzeProvider].
final movimentiProvider = FutureProvider.autoDispose<PagedResult<MovimentoDto>>(
  (ref) async {
    final client = ref.watch(magazzinoApiClientProvider);
    return client.getMovimenti(pageSize: 30);
  },
);

/// The current technician's assigned van warehouse, from
/// `GET /api/magazzino/furgone/{userId}` — the default source for rapportino material lines
/// (`step_materiali_fold.dart`). Null when this user has no furgone assigned; the caller falls
/// back to an explicit picker in that case.
///
/// Online it reads through, so an office reassignment reaches the phone on the next visit rather
/// than after the next sync. Offline — or online with a request that never arrived / a server fault
/// — it answers from the `magazzini` mirror, where `assegnatoUserId` travels on the warehouse row
/// itself: the assignment is a device-local lookup, never a live call. Null there means either "no
/// van assigned" or "no mirror yet"; both leave the line's source unset instead of blocking the
/// add, and the picker below says why when it cannot offer the alternatives.
///
/// The fallback matters more here than the null it produces: without it a technician with a weak
/// signal got *no* default source and had to pick a warehouse by hand on every material line, for
/// an assignment the phone was already holding.
final furgoneDiUserProvider = FutureProvider.autoDispose
    .family<MagazzinoDto?, String>((ref, userId) async {
      Future<MagazzinoDto?> fromMirror() async {
        final db = ref.watch(appDatabaseProvider);
        final row =
            await (db.select(db.magazzini)..where(
                  (w) => w.tipo.equals('Furgone') & w.assegnatoUserId.equals(userId),
                )..limit(1))
                .getSingleOrNull();
        return row == null ? null : _fromMirror(row);
      }

      if (ref.watch(isOnlineProvider)) {
        try {
          return await ref.watch(magazzinoApiClientProvider).getFurgoneByUser(userId);
        } catch (e) {
          if (!isTransportOrServerFault(e)) rethrow;
        }
      }
      return fromMirror();
    });

/// All warehouses (for admin CRUD and the "cambia magazzino" override picker).
///
/// Online it reads through — the office may have just created a Sede, and a connected device
/// shows the server's copy. Offline it answers from the `magazzini` mirror, so a material line
/// picked up on site can still name the Sede it came from.
///
/// Nothing cached is not the same as nothing existing: an empty mirror throws
/// [MagazziniOfflineException] rather than returning `[]`, because the picker renders an empty
/// list as "Nessun magazzino disponibile." — a false statement about the tenant's stock that a
/// technician would act on.
final magazziniProvider = FutureProvider.autoDispose<List<MagazzinoDto>>((
  ref,
) async {
  if (ref.watch(isOnlineProvider)) {
    return ref.watch(magazzinoApiClientProvider).getMagazzini();
  }
  final db = ref.watch(appDatabaseProvider);
  final rows =
      await (db.select(
        db.magazzini,
      )..orderBy([(w) => OrderingTerm.asc(w.nome)])).get();
  if (rows.isEmpty) throw const MagazziniOfflineException();
  return rows.map(_fromMirror).toList(growable: false);
});

/// The warehouses live on the server but this device has never downloaded them.
///
/// `humanErrorMessage` folds anything that is not a `DioException` into "Errore imprevisto", which
/// would be a lie about the cause here — the radio is off, not the app broken. The picker
/// (`step_materiali_fold.dart`) renders this one's own message instead.
class MagazziniOfflineException implements Exception {
  const MagazziniOfflineException();

  String get message =>
      'Magazzini non ancora scaricati su questo dispositivo: riprova quando torni online.';

  @override
  String toString() => message;
}

/// A mirror row as the DTO the rest of the app already speaks.
///
/// `indirizzo`/`note` are not in the sync member — nothing offline reads them, and the admin
/// screens that show them are live-only — so they are null here rather than guessed.
MagazzinoDto _fromMirror(MagazziniData row) => MagazzinoDto(
  id: row.id,
  nome: row.nome,
  tipo: row.tipo,
  assegnatoUserId: row.assegnatoUserId,
  isActive: row.isActive,
);

/// Distinct non-null category values from the materiali table.
final materialiCategoriesProvider = StreamProvider.autoDispose<List<String>>((
  ref,
) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(
    db.materiali,
  )..where((m) => m.isActive.equals(true))).watch().map((rows) {
    final cats =
        rows
            .map((r) => r.category)
            .whereType<String>()
            .where((c) => c.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return cats;
  });
});
