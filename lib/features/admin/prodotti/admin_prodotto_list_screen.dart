// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/utils/error_message.dart' show isTransportOrServerFault;
import '../../../core/widgets/widgets.dart';
import '../../../data/reference/reference_cache_repository.dart';
import '../../../data/sync/connectivity_provider.dart';
import '../../../data/sync/sync_service.dart' show appDatabaseProvider;
import '../../ticket/ticket_detail_api_client.dart' show TicketDetailOfflineException;
import '../admin_api_client.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

/// The list's search text. Its own provider (not a family argument on the list provider) so the
/// form screen can keep invalidating [adminProdottiAssistenzaProvider] without knowing the query.
final adminProdottiQueryProvider = StateProvider.autoDispose<String>((ref) => '');

/// The Asset list's rows, plus where they came from.
///
/// [fromMirror] drives [MirrorNotice]: the sync payload is scoped, so a mirrored list is a partial
/// one and its "N totali" must not read as the tenant's whole asset book.
class ProdottoListRows {
  const ProdottoListRows(this.rows, {required this.fromMirror});

  final List<Map<String, dynamic>> rows;
  final bool fromMirror;
}

/// Prodotti assistenza — server-first, mirror when it cannot be reached.
///
/// Online the search term is sent as `q` and the server searches every row. Offline the mirror is
/// searched here with the same three fields the server matches on (name, codice, categoria), so a
/// technician who types a serial-adjacent code on site still gets an answer instead of a spinner.
///
/// The mirror has no `prezzoVendita` (it is not in the sync payload), so mirrored rows show no
/// price — absent, not zero.
final adminProdottiAssistenzaProvider = FutureProvider.autoDispose<ProdottoListRows>((ref) async {
  final q = ref.watch(adminProdottiQueryProvider);

  Future<ProdottoListRows> fromMirror() async {
    final db = ref.watch(appDatabaseProvider);
    final rows = await ref.watch(referenceCacheProvider).allProdottiAssistenza();
    if (rows.isEmpty && await db.getLastSync() == null) {
      throw const TicketDetailOfflineException();
    }
    // The row shows the customer's *name*; the mirror carries only the id. Read every customer
    // (inactive ones included — an asset can belong to a customer the office has since archived,
    // and '—' there would claim the asset belongs to nobody).
    final customers = {
      for (final c in await db.select(db.customers).get()) c.id: c.companyName,
    };
    final needle = q.toLowerCase();
    final matches = needle.isEmpty
        ? rows
        : rows
              .where(
                (p) =>
                    p.name.toLowerCase().contains(needle) ||
                    (p.codice ?? '').toLowerCase().contains(needle) ||
                    (p.categoria ?? '').toLowerCase().contains(needle),
              )
              .toList();
    return ProdottoListRows([
      for (final p in matches)
        {
          'id': p.id,
          'name': p.name,
          'customerId': p.customerId,
          'customerName': customers[p.customerId] ?? '—',
          'isActive': p.isActive,
          'codice': p.codice,
          'categoria': p.categoria,
          'serialNumber': p.serialNumber,
          'marchio': p.marchio,
          'externalId': p.externalId,
        },
    ], fromMirror: true);
  }

  if (ref.watch(isOnlineProvider)) {
    try {
      return ProdottoListRows(
        await ref.watch(adminApiClientProvider).fetchProdottiAssistenza(q: q),
        fromMirror: false,
      );
    } catch (e) {
      if (!isTransportOrServerFault(e)) rethrow;
    }
  }
  return fromMirror();
});

/// Admin prodotto assistenza list — server-first, mirror when it cannot be reached.
class AdminProdottoListScreen extends ConsumerWidget {
  const AdminProdottoListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prodottiAsync = ref.watch(adminProdottiAssistenzaProvider);

    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: prodottiAsync.when(
          // A new search term reloads the provider; keep the previous list (and the search field's
          // focus and text, which live in the body) on screen instead of swapping in a spinner.
          skipLoadingOnReload: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => e is TicketDetailOfflineException
              ? const UnavailableState(
                  icon: LucideIcons.wrench,
                  titolo: 'Asset non disponibili offline',
                  motivo:
                      'Questo dispositivo non ha ancora scaricato gli asset. Apri questa lista '
                      'con una connessione attiva per averli anche offline.',
                )
              : ErrorState(onRetry: () => ref.invalidate(adminProdottiAssistenzaProvider)),
          data: (data) => _ProdottoListBody(rows: data),
        ),
      ),
      floatingActionButton: Padding(
        // navClearance alone, not minus navGap — see admin_cantiere_list_screen.dart's comment on
        // this same change.
        padding: EdgeInsets.only(bottom: context.navClearance),
        child: AppFab(
          tooltip: 'Nuovo asset',
          onPressed: () => context.push('/altro/prodotti/nuovo'),
        ),
      ),
    );
  }
}

class _ProdottoListBody extends ConsumerStatefulWidget {
  const _ProdottoListBody({required this.rows});

  final ProdottoListRows rows;

  @override
  ConsumerState<_ProdottoListBody> createState() => _ProdottoListBodyState();
}

class _ProdottoListBodyState extends ConsumerState<_ProdottoListBody> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) ref.read(adminProdottiQueryProvider.notifier).state = q.trim();
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.rows.rows;
    final searching = ref.watch(adminProdottiQueryProvider).isNotEmpty;

    return RefreshIndicator(
      onRefresh: () => ref.refresh(adminProdottiAssistenzaProvider.future),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: ScreenHeader(
              title: 'Asset',
              subtitle: '${filtered.length} totali',
              showBack: true,
            ),
          ),
          SliverToBoxAdapter(
            child: AppSearchBar(
              controller: _searchCtrl,
              hint: 'Cerca per nome o codice…',
              onChanged: _onQueryChanged,
            ),
          ),
          if (widget.rows.fromMirror && filtered.isNotEmpty)
            const SliverToBoxAdapter(child: MirrorNotice(what: 'asset')),
          if (filtered.isEmpty)
            SliverToBoxAdapter(
              child: EmptyState(
                icon: LucideIcons.wrench,
                title: 'Nessun asset',
                body: searching
                    ? 'Nessun asset corrisponde alla ricerca.'
                    : 'Crea un nuovo asset con il pulsante +.',
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate((context, i) {
                final prodotto = filtered[i];
                final name = prodotto['name'] as String? ?? '';
                // The server resolves the name on the row; the customer list is not fetched here
                // (a technician does not hold customer.read, and walking it only to map ids is the
                // anti-pattern the list endpoints exist to avoid).
                final customerName = prodotto['customerName'] as String? ?? '—';
                final isActive = prodotto['isActive'] as bool? ?? true;
                final codice = prodotto['codice'] as String?;
                final categoria = prodotto['categoria'] as String?;
                final prezzoVendita = prodotto['prezzoVendita'];
                return _ProdottoRow(
                  name: name,
                  customerName: customerName,
                  codice: codice,
                  categoria: categoria,
                  prezzoVendita: prezzoVendita is num ? prezzoVendita : null,
                  isActive: isActive,
                  isLast: i == filtered.length - 1,
                  onTap: () => context.push('/altro/prodotti/${prodotto['id']}', extra: prodotto),
                );
              }, childCount: filtered.length),
            ),
          SliverPadding(padding: EdgeInsets.only(bottom: context.navClearance)),
        ],
      ),
    );
  }
}

class _ProdottoRow extends StatelessWidget {
  const _ProdottoRow({
    required this.name,
    required this.customerName,
    required this.codice,
    required this.categoria,
    required this.prezzoVendita,
    required this.isActive,
    required this.isLast,
    required this.onTap,
  });

  final String name;
  final String customerName;
  final String? codice;
  final String? categoria;
  final num? prezzoVendita;
  final bool isActive;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Gap 4 of the feature audit: the row used to show only name + customer, with no way to tell
    // products apart by any commercial attribute on device — mirrors the materiale row's own
    // "codice · categoria" subtitle + price meta shape (admin_materiale_list_screen.dart).
    final subtitleParts = [
      customerName,
      if (categoria != null && categoria!.isNotEmpty) categoria!,
    ];
    final priceLabel = prezzoVendita != null ? '€${prezzoVendita!.toStringAsFixed(2)}' : null;

    return ListRow(
      leading: const RowIconTile(icon: LucideIcons.wrench),
      title: codice != null && codice!.isNotEmpty ? '$codice · $name' : name,
      subtitle: subtitleParts.join(' · '),
      meta: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (priceLabel != null)
            Text(
              priceLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.colors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          // Only when inactive: an active product is the ordinary state of every row on this
          // list, and printing "Attivo" on all of them would be the pill making the same noise
          // the accent strap grammar refuses to make — it should mark the row that differs, not
          // every row.
          if (!isActive)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: StatusPill(stato: 'Inattivo', small: true),
            ),
        ],
      ),
      showDivider: !isLast,
      onTap: onTap,
    );
  }
}
