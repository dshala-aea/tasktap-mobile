// dart format width=100
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/widgets/widgets.dart';
import '../../../data/local/app_database.dart';
import '../../../data/materiali/materiale_barcode_lookup.dart';
import '../../../data/sync/sync_service.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// All materiali from Drift cache, alphabetical.
///
/// Reads the local mirror the sync now fills.
final adminMaterialiProvider = StreamProvider.autoDispose<List<MaterialiData>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.materiali)..orderBy([(m) => OrderingTerm.asc(m.name)])).watch();
});

/// Admin materiale list — with search, category filter, FAB.
class AdminMaterialeListScreen extends StatefulWidget {
  const AdminMaterialeListScreen({super.key});

  @override
  State<AdminMaterialeListScreen> createState() => _AdminMaterialeListScreenState();
}

class _AdminMaterialeListScreenState extends State<AdminMaterialeListScreen> {
  String _query = '';
  String? _selectedCategory;
  bool _showInactive = false;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: _AdminMaterialeListBody(
          query: _query,
          selectedCategory: _selectedCategory,
          showInactive: _showInactive,
          searchCtrl: _searchCtrl,
          onQueryChanged: (q) => setState(() => _query = q),
          onCategoryChanged: (c) => setState(() => _selectedCategory = c),
          onShowInactiveChanged: (v) => setState(() => _showInactive = v),
        ),
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: context.navClearance - AppRack.navGap),
        child: AppFab(
          tooltip: 'Nuovo materiale',
          onPressed: () => context.push('/altro/magazzino/nuovo'),
        ),
      ),
    );
  }
}

class _AdminMaterialeListBody extends ConsumerWidget {
  const _AdminMaterialeListBody({
    required this.query,
    required this.selectedCategory,
    required this.showInactive,
    required this.searchCtrl,
    required this.onQueryChanged,
    required this.onCategoryChanged,
    required this.onShowInactiveChanged,
  });

  final String query;
  final String? selectedCategory;
  final bool showInactive;
  final TextEditingController searchCtrl;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<bool> onShowInactiveChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final materialiAsync = ref.watch(adminMaterialiProvider);
    final allMateriali = materialiAsync.valueOrNull ?? [];

    // Collect unique categories for filter chips
    final categories =
        allMateriali
            .where((m) => m.category != null && m.category!.isNotEmpty)
            .map((m) => m.category!)
            .toSet()
            .toList()
          ..sort();

    final filtered = allMateriali.where((m) {
      final matchActive = showInactive || m.isActive;
      final matchCategory = selectedCategory == null || m.category == selectedCategory;
      final matchQuery =
          query.isEmpty ||
          m.name.toLowerCase().contains(query.toLowerCase()) ||
          m.code.toLowerCase().contains(query.toLowerCase()) ||
          (m.description?.toLowerCase().contains(query.toLowerCase()) ?? false);
      return matchActive && matchCategory && matchQuery;
    }).toList();

    return RefreshIndicator(
      onRefresh: () => ref.read(syncProvider.notifier).performSync(),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: ScreenHeader(
              title: 'Magazzino',
              subtitle: '${filtered.length} totali',
              showBack: true,
              actions: [
                // Gap 3/4 of the feature audit: the stock-aware screen (quantities, movements,
                // carico/scarico/trasferimento) existed with no route pointing at it.
                HeaderIconBtn(
                  icon: LucideIcons.arrowLeftRight,
                  label: 'Giacenze e movimenti',
                  glass: true,
                  onTap: () => context.push('/altro/magazzino/giacenze'),
                ),
                // Gap 2: warehouse (Sede/Furgone) admin CRUD, distinct from this materiali
                // catalogue.
                HeaderIconBtn(
                  icon: LucideIcons.warehouse,
                  label: 'Magazzini',
                  glass: true,
                  onTap: () => context.push('/altro/magazzino/magazzini'),
                ),
                HeaderIconBtn(
                  icon: showInactive ? LucideIcons.eye : LucideIcons.eyeOff,
                  label: showInactive ? 'Nascondi inattivi' : 'Mostra inattivi',
                  glass: true,
                  onTap: () => onShowInactiveChanged(!showInactive),
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: Row(
              children: [
                Expanded(
                  child: AppSearchBar(
                    controller: searchCtrl,
                    hint: 'Cerca per nome, codice o descrizione…',
                    onChanged: onQueryChanged,
                    // Own right margin dropped to a small gap — the scan button follows it now,
                    // rather than the field sitting flush against the screen edge.
                    margin: const EdgeInsets.fromLTRB(19, 0, 8, 12),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 12),
                  child: IconButton(
                    icon: const Icon(LucideIcons.scanLine),
                    tooltip: 'Scansiona codice',
                    onPressed: () async {
                      final match = await scanForMateriale(context, ref, title: 'Cerca materiale');
                      if (match == null) return;
                      searchCtrl.text = match.code;
                      onQueryChanged(match.code);
                    },
                  ),
                ),
              ],
            ),
          ),
          // ── Category filter ──────────────────────────────────────────────
          if (categories.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pagePadding,
                  0,
                  AppSpacing.pagePadding,
                  AppSpacing.md,
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      AppChip(
                        label: 'Tutti',
                        active: selectedCategory == null,
                        onTap: () => onCategoryChanged(null),
                      ),
                      const SizedBox(width: 8),
                      for (final cat in categories) ...[
                        AppChip(
                          label: cat,
                          active: selectedCategory == cat,
                          onTap: () => onCategoryChanged(cat),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          if (materialiAsync.isLoading)
            const SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.xxxl),
                  child: CircularProgressIndicator(),
                ),
              ),
            )
          else if (filtered.isEmpty)
            SliverToBoxAdapter(
              child: UnavailableState(
                icon: LucideIcons.package,
                titolo: 'Catalogo materiali non disponibile',
                motivo:
                    'Il catalogo materiali non è ancora sincronizzato sul '
                    'dispositivo. I materiali creati con il pulsante + vengono '
                    'salvati sul server ma non compariranno in questa lista '
                    'finché la sincronizzazione non sarà collegata.',
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate((context, i) {
                final materiale = filtered[i];
                return _AdminMaterialeRow(materiale: materiale, isLast: i == filtered.length - 1);
              }, childCount: filtered.length),
            ),
          SliverPadding(padding: EdgeInsets.only(bottom: context.navClearance)),
        ],
      ),
    );
  }
}

class _AdminMaterialeRow extends StatelessWidget {
  const _AdminMaterialeRow({required this.materiale, required this.isLast});

  final MaterialiData materiale;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final catLabel = materiale.category ?? '—';
    final priceLabel = materiale.salePrice != null
        ? '€${materiale.salePrice!.toStringAsFixed(2)}'
        : '—';

    return ListRow(
      leading: RowIconTile(
        icon: materiale.imageUrl == null ? LucideIcons.package : null,
        child: materiale.imageUrl != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(AppRack.insetRadius),
                child: Image.network(
                  materiale.imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      Icon(LucideIcons.package, size: 20, color: AppColors.onDarkMuted),
                ),
              )
            : null,
      ),
      title: materiale.name,
      subtitle: '${materiale.code} · $catLabel',
      meta: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            priceLabel,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: context.colors.ink, fontWeight: FontWeight.w600),
          ),
          if (!materiale.isActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                color: context.colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('Inattivo', style: TextStyle(fontSize: 10, color: context.colors.red)),
            ),
        ],
      ),
      showDivider: !isLast,
      onTap: () => context.push('/altro/magazzino/${materiale.id}'),
    );
  }
}
