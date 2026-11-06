// dart format width=100
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_rack.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';
import 'package:tasktap_mobile/core/theme/app_text_styles.dart';

import '../../../core/widgets/widgets.dart';
import '../../../data/local/app_database.dart';
import '../../../data/materiali/materiale_barcode_lookup.dart';
import '../../../data/sync/sync_freshness_provider.dart';
import '../../../data/sync/sync_service.dart';

/// All materiali from Drift cache, alphabetical.
///
/// Reads the local mirror the sync now fills.
final adminMaterialiProvider = StreamProvider.autoDispose<List<MaterialiData>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.materiali)..orderBy([(m) => OrderingTerm.asc(m.name)])).watch();
});

/// The status preset behind the quick chips. Defaults to [attivi]: the screen has always opened
/// on the active catalogue, and `show/hide inactive` writes this same value.
enum _MaterialeStatusFilter { tutti, attivi, inattivi }

extension on _MaterialeStatusFilter {
  String get label => switch (this) {
    _MaterialeStatusFilter.tutti => 'Tutti',
    _MaterialeStatusFilter.attivi => 'Attivi',
    _MaterialeStatusFilter.inattivi => 'Inattivi',
  };
}

/// The combinable facets kept in the `Filtri` sheet. Category used to be the quick-chip row; it now
/// lives here so the chips match the prototype's status presets.
class _MaterialeFilters {
  const _MaterialeFilters({this.status = _MaterialeStatusFilter.attivi, this.category});

  final _MaterialeStatusFilter status;
  final String? category;

  _MaterialeFilters copyWith({_MaterialeStatusFilter? status}) {
    return _MaterialeFilters(status: status ?? this.status, category: category);
  }

  bool get hasFacets => category != null;
}

/// Admin materiale list — with search, status/category filters and `Nuovo`.
///
/// Rebuilt on the wave-0 list shell: header (title, subtitle, the three existing header actions and
/// the gated `Nuovo`) → search (+ barcode scan) → status chips + `Filtri` → `Attivi`/`Inattivi`
/// groups → summary. Stock (`giacenza`, `scorta minima`, `sotto scorta`) has no local mirror, so
/// the stock chip/group/row line and its summary half are dropped; the `Giacenze e movimenti`
/// header action keeps stock reachable on demand.
class AdminMaterialeListScreen extends StatefulWidget {
  const AdminMaterialeListScreen({super.key});

  @override
  State<AdminMaterialeListScreen> createState() => _AdminMaterialeListScreenState();
}

class _AdminMaterialeListScreenState extends State<AdminMaterialeListScreen> {
  String _query = '';
  _MaterialeFilters _filters = const _MaterialeFilters();
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<_MaterialeFilters>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _MaterialeFilterSheet(initial: _filters),
    );
    if (result != null && mounted) setState(() => _filters = result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: _AdminMaterialeListBody(
          query: _query,
          filters: _filters,
          searchCtrl: _searchCtrl,
          onQueryChanged: (q) => setState(() => _query = q),
          onFiltersChanged: (f) => setState(() => _filters = f),
          onOpenFilters: _openFilters,
        ),
      ),
    );
  }
}

class _AdminMaterialeListBody extends ConsumerWidget {
  const _AdminMaterialeListBody({
    required this.query,
    required this.filters,
    required this.searchCtrl,
    required this.onQueryChanged,
    required this.onFiltersChanged,
    required this.onOpenFilters,
  });

  final String query;
  final _MaterialeFilters filters;
  final TextEditingController searchCtrl;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<_MaterialeFilters> onFiltersChanged;
  final VoidCallback onOpenFilters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final materialiAsync = ref.watch(adminMaterialiProvider);
    final allMateriali = materialiAsync.valueOrNull ?? const <MaterialiData>[];

    final filtered = allMateriali.where((m) {
      if (!_matchesStatus(m, filters.status)) return false;
      if (filters.category != null && m.category?.trim() != filters.category) {
        return false;
      }
      return _matchesQuery(m, query);
    }).toList();

    final activeRows = filtered.where((m) => m.isActive).toList();
    final inactiveRows = filtered.where((m) => !m.isActive).toList();

    final groups = <ListGroupData>[
      if (activeRows.isNotEmpty)
        ListGroupData(
          title: 'Attivi',
          count: activeRows.length,
          rows: activeRows.map((m) => _row(context, m)).toList(),
        ),
      if (inactiveRows.isNotEmpty)
        ListGroupData(
          title: 'Inattivi',
          count: inactiveRows.length,
          rows: inactiveRows.map((m) => _row(context, m)).toList(),
        ),
    ];

    final neverSynced = ref.watch(hasSyncedAtLeastOnceProvider).valueOrNull == false;
    final showingInactive = filters.status != _MaterialeStatusFilter.attivi;

    Future<void> onRefresh() => refreshWithFeedback(context, ref);

    return Column(
      children: [
        const OfflineSyncBanner(),
        ScreenHeader(
          title: 'Materiali',
          subtitle: "Cosa c'è, cosa manca, quanto costa.",
          subtitleMaxLines: 3,
          showBack: true,
          actions: [
            // The only entry points to the stock/movements screen and warehouse admin. The
            // prototype shows neither, but dropping them would strand both screens.
            HeaderIconBtn(
              icon: LucideIcons.arrowLeftRight,
              label: 'Giacenze e movimenti',
              glass: true,
              onTap: () => context.push('/altro/magazzino/giacenze'),
            ),
            HeaderIconBtn(
              icon: LucideIcons.warehouse,
              label: 'Magazzini',
              glass: true,
              onTap: () => context.push('/altro/magazzino/magazzini'),
            ),
            HeaderIconBtn(
              icon: showingInactive ? LucideIcons.eye : LucideIcons.eyeOff,
              label: showingInactive ? 'Nascondi inattivi' : 'Mostra inattivi',
              glass: true,
              onTap: () => onFiltersChanged(
                filters.copyWith(
                  status: showingInactive
                      ? _MaterialeStatusFilter.attivi
                      : _MaterialeStatusFilter.tutti,
                ),
              ),
            ),
            CapabilityGate(
              capability: 'magazzino.article.write',
              child: ListHeaderAction(
                label: 'Nuovo',
                onPressed: () => context.push('/altro/magazzino/nuovo'),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: AppSearchBar(
                controller: searchCtrl,
                hint: 'Cerca codice, nome o categoria…',
                onChanged: onQueryChanged,
                // The scan button follows the field rather than the field sitting flush against
                // the screen edge.
                margin: const EdgeInsets.fromLTRB(
                  AppSpacing.pagePadding,
                  0,
                  AppSpacing.sm,
                  AppSpacing.md,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm, bottom: AppSpacing.md),
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
        ListFilterRow(
          filters: const [
            ListFilterChipData(label: 'Tutti'),
            ListFilterChipData(label: 'Attivi'),
            ListFilterChipData(label: 'Inattivi'),
          ],
          activeIndex: filters.status.index,
          onSelected: (chip) => onFiltersChanged(
            filters.copyWith(
              status: _MaterialeStatusFilter.values.firstWhere((s) => s.label == chip.label),
            ),
          ),
          onOpenFilters: onOpenFilters,
        ),
        Expanded(
          child: _body(
            context: context,
            ref: ref,
            materialiAsync: materialiAsync,
            groups: groups,
            allMateriali: allMateriali,
            filtered: filtered,
            activeCount: activeRows.length,
            query: query,
            filters: filters,
            neverSynced: neverSynced,
            onRefresh: onRefresh,
          ),
        ),
      ],
    );
  }

  Widget _body({
    required BuildContext context,
    required WidgetRef ref,
    required AsyncValue<List<MaterialiData>> materialiAsync,
    required List<ListGroupData> groups,
    required List<MaterialiData> allMateriali,
    required List<MaterialiData> filtered,
    required int activeCount,
    required String query,
    required _MaterialeFilters filters,
    required bool neverSynced,
    required Future<void> Function() onRefresh,
  }) {
    if (materialiAsync.isLoading && !materialiAsync.hasValue) {
      return _scrollable(context, const ListLoadingSkeleton(), onRefresh);
    }

    if (materialiAsync.hasError && !materialiAsync.hasValue) {
      return _scrollable(
        context,
        UnavailableState(
          icon: LucideIcons.alertTriangle,
          titolo: 'Materiali non disponibili',
          motivo: 'Non è stato possibile leggere il catalogo materiali da questo telefono.',
          action: AppButton(
            label: 'Riprova',
            onPressed: () => ref.invalidate(adminMaterialiProvider),
          ),
        ),
        onRefresh,
      );
    }

    if (groups.isEmpty) {
      return _scrollable(
        context,
        _emptyState(
          query: query,
          filters: filters,
          allMateriali: allMateriali,
          neverSynced: neverSynced,
        ),
        onRefresh,
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          for (final group in groups) ...[
            SliverToBoxAdapter(
              child: _framed(
                child: ListGroupHeader(title: group.title!, count: group.count),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => KeyedSubtree(
                    key: group.rows[i].rowKey,
                    child: ListDocumentRow(data: group.rows[i]),
                  ),
                  childCount: group.rows.length,
                ),
              ),
            ),
          ],
          SliverToBoxAdapter(
            child: _framed(
              child: ListSummaryFooter(
                data: ListSummaryData(
                  left: _materialiLabel(filtered.length),
                  right: _attiviLabel(activeCount),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(child: SizedBox(height: context.navClearance)),
        ],
      ),
    );
  }

  Widget _scrollable(BuildContext context, Widget child, Future<void> Function() onRefresh) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Center(
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: child),
          ),
          SizedBox(height: context.navClearance),
        ],
      ),
    );
  }

  Widget _framed({required Widget child}) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
          child: child,
        ),
      ),
    );
  }

  Widget _emptyState({
    required String query,
    required _MaterialeFilters filters,
    required List<MaterialiData> allMateriali,
    required bool neverSynced,
  }) {
    // A search that matched nothing is not a sync problem — even on a mirror that has never
    // synced, the technician's query is what produced zero rows.
    if (query.isNotEmpty || filters.hasFacets || allMateriali.isNotEmpty) {
      return EmptyState(
        icon: LucideIcons.searchX,
        title: 'Nessun risultato',
        body: query.isNotEmpty
            ? 'Nessun materiale corrisponde a "$query".'
            : 'Nessun materiale corrisponde a ricerca e filtri attivi.',
      );
    }
    if (neverSynced) {
      return const UnavailableState(
        icon: LucideIcons.cloudOff,
        titolo: 'Catalogo materiali non ancora scaricato',
        motivo:
            'Questo telefono non ha ancora completato una sincronizzazione. '
            'Il catalogo comparirà qui dopo la prossima: trascina in basso per '
            'aggiornare.',
      );
    }
    return const EmptyState(
      icon: LucideIcons.package,
      title: 'Catalogo materiali vuoto',
      body:
          'Non è ancora stato creato nessun materiale. Usa il pulsante Nuovo per '
          'aggiungerne uno.',
    );
  }

  static bool _matchesStatus(MaterialiData m, _MaterialeStatusFilter status) {
    return switch (status) {
      _MaterialeStatusFilter.tutti => true,
      _MaterialeStatusFilter.attivi => m.isActive,
      _MaterialeStatusFilter.inattivi => !m.isActive,
    };
  }

  static bool _matchesQuery(MaterialiData m, String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return m.name.toLowerCase().contains(q) ||
        m.code.toLowerCase().contains(q) ||
        (m.category?.toLowerCase().contains(q) ?? false) ||
        (m.description?.toLowerCase().contains(q) ?? false);
  }

  static ListRowData _row(BuildContext context, MaterialiData materiale) {
    final meta = <String>[
      if (materiale.code.trim().isNotEmpty) materiale.code,
      if (materiale.category != null && materiale.category!.trim().isNotEmpty)
        materiale.category!.trim(),
      if (materiale.salePrice != null) _priceLabel(materiale.salePrice!),
    ];

    return ListRowData(
      title: materiale.name,
      meta: meta.isEmpty ? null : meta.join(' · '),
      status: materiale.isActive ? 'Attivo' : 'Inattivo',
      statusTone: materiale.isActive ? ListStatusTone.good : ListStatusTone.bad,
      onTap: () => context.push('/altro/magazzino/${materiale.id}'),
    );
  }

  static String _priceLabel(double value) => '€ ${value.toStringAsFixed(2).replaceAll('.', ',')}';

  static String _materialiLabel(int count) => count == 1 ? '1 materiale' : '$count materiali';

  static String _attiviLabel(int count) => count == 1 ? '1 attivo' : '$count attivi';
}

class _MaterialeFilterSheet extends ConsumerStatefulWidget {
  const _MaterialeFilterSheet({required this.initial});

  final _MaterialeFilters initial;

  @override
  ConsumerState<_MaterialeFilterSheet> createState() => _MaterialeFilterSheetState();
}

class _MaterialeFilterSheetState extends ConsumerState<_MaterialeFilterSheet> {
  late _MaterialeStatusFilter _status = widget.initial.status;
  late String? _category = widget.initial.category;

  @override
  Widget build(BuildContext context) {
    final materiali = ref.watch(adminMaterialiProvider).valueOrNull ?? const [];
    final categories = {
      for (final m in materiali)
        if (m.category != null && m.category!.trim().isNotEmpty) m.category!.trim(),
    }.toList()..sort();
    if (_category != null && !categories.contains(_category)) categories.add(_category!);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.pagePadding,
        AppSpacing.pagePadding,
        MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).viewPadding.bottom +
            AppSpacing.pagePadding,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.md),
              child: SheetHandle(),
            ),
            Text('Filtri', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            AppFieldShell(
              label: 'Stato',
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final status in _MaterialeStatusFilter.values)
                    _FilterChoice(
                      key: Key('materiali-filter-status-${status.name}'),
                      label: status.label,
                      active: _status == status,
                      onTap: () => setState(() => _status = status),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppFieldShell(
              label: 'Categoria',
              child: DropdownButtonFormField<String?>(
                key: const Key('materiali-filter-category'),
                // ignore: deprecated_member_use — controlled field, needs value not initialValue
                value: _category,
                isExpanded: true,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Tutte')),
                  ...categories.map(
                    (category) => DropdownMenuItem(value: category, child: Text(category)),
                  ),
                ],
                onChanged: (value) => setState(() => _category = value),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: AppButton.ghost(
                    key: const Key('materiali-filter-reset'),
                    label: 'Azzera',
                    onPressed: () => Navigator.pop(context, const _MaterialeFilters()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    key: const Key('materiali-filter-apply'),
                    label: 'Applica',
                    onPressed: () => Navigator.pop(
                      context,
                      _MaterialeFilters(status: _status, category: _category),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChoice extends StatelessWidget {
  const _FilterChoice({super.key, required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: AppTappable(
            onTap: onTap,
            borderRadius: AppRack.freeShape,
            color: active ? colors.ink : colors.surface,
            border: Border.all(color: active ? colors.ink : colors.borderLight),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.docCode.copyWith(
                fontSize: 8,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.32,
                color: active ? colors.surface : colors.inkMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
