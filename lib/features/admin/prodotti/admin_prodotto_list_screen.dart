// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/widgets/widgets.dart';
import '../../../data/reference/reference_cache_repository.dart';
import '../../../data/sync/connectivity_provider.dart';
import '../admin_api_client.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// The list's search text. Its own provider (not a family argument on the list provider) so the
/// form screen can keep invalidating [adminProdottiAssistenzaProvider] without knowing the query.
final adminProdottiQueryProvider = StateProvider.autoDispose<String>((ref) => '');

/// Prodotti assistenza for the Asset list: live from the API, or from the Drift mirror when there
/// is no signal.
///
/// Offline the mirror holds the assets of the customers this phone carries — a real subset of the
/// tenant, not the whole book — so it answers with those and the screen says so. It is deliberately
/// *not* used as a fallback for a failed live call while online: this is a browse list, and there
/// the error plus its retry is the honest answer (unlike the customer screen, where the mirrored
/// rows for one customer are complete by construction).
///
/// Online the search text goes to the server as `q`, so it searches every row instead of the client
/// filtering a first page; offline the same text filters the mirrored rows locally.
final adminProdottiAssistenzaProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((
  ref,
) async {
  final q = ref.watch(adminProdottiQueryProvider);

  if (!ref.watch(isOnlineProvider)) {
    final rows = await ref.read(referenceCacheProvider).allProdottiWithCustomer();
    final term = q.trim().toLowerCase();
    bool matches(String? value) => term.isEmpty || (value ?? '').toLowerCase().contains(term);
    return [
      for (final (p, customerName) in rows)
        if (matches(p.name) || matches(p.codice))
          {
            'id': p.id,
            'name': p.name,
            'isActive': p.isActive,
            'codice': p.codice,
            'categoria': p.categoria,
            'serialNumber': p.serialNumber,
            // The row prints this; without it an offline list cannot say whose asset it is.
            'customerName': customerName ?? '—',
          },
    ];
  }

  return ref.watch(adminApiClientProvider).fetchProdottiAssistenza(q: q);
});

/// Admin prodotto assistenza list — live online, mirrored offline.
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
          error: (e, _) =>
              ErrorState(onRetry: () => ref.invalidate(adminProdottiAssistenzaProvider)),
          data: (prodotti) => _ProdottoListBody(prodotti: prodotti),
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
  const _ProdottoListBody({required this.prodotti});

  final List<Map<String, dynamic>> prodotti;

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
    final filtered = widget.prodotti;
    final searching = ref.watch(adminProdottiQueryProvider).isNotEmpty;
    // Offline the list comes from the mirror, which only holds this device's customers. Saying so
    // is the difference between "these are the tenant's assets" and "these are the ones I can see".
    final offline = !ref.watch(isOnlineProvider);

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
          if (offline)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pagePadding,
                  0,
                  AppSpacing.pagePadding,
                  AppSpacing.md,
                ),
                child: Text(
                  'Offline: solo gli asset dei clienti sincronizzati su questo telefono.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: context.colors.inkMuted),
                ),
              ),
            ),
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
