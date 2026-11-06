// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_rack.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/entitlements/entitlement_providers.dart' show cachedEntitlementProvider;
import '../../../data/local/app_database.dart' show Colleague;
import '../../../data/magazzino/magazzino_api_client.dart';
import '../../../presentation/providers/schedule_providers.dart' show allColleaguesProvider;
import '../../magazzino/magazzino_providers.dart';

// ══════════════════════════════════════════════════════════════════════════════
// AdminMagazzinoListScreen — warehouse (Magazzino: Sede/Furgone) admin list.
//
// Distinct from the materiali *catalogue* CRUD at `admin_materiale_*` — this manages the
// warehouses themselves (name, type, assigned technician, address). `magazziniProvider` already
// reads the server online and falls back to the synced `magazzini` mirror, so the screen keeps its
// existing read; no extra endpoint/table is involved.
//
// The prototype's `articoli` / `sotto scorta` lines are absent: `GET /api/magazzino` returns the
// entity, which carries no stock counts (those live in the separate giacenze endpoint, a
// per-warehouse read this list must not open). The row therefore shows name, place and the
// type/active stamp only.
// ══════════════════════════════════════════════════════════════════════════════

/// The prototype's quick presets. `Principali`/`Secondari` are the two groups the list shows,
/// derived from the warehouse's own `tipo` (`Sede` / `Furgone`).
enum _MagazzinoStatusFilter { tutti, principali, secondari }

extension on _MagazzinoStatusFilter {
  String get id => name;

  String get label => switch (this) {
    _MagazzinoStatusFilter.tutti => 'Tutti',
    _MagazzinoStatusFilter.principali => 'Principali',
    _MagazzinoStatusFilter.secondari => 'Secondari',
  };

  /// The `tipo` label the sheet's `Tipo` field shows for this preset, or null for "both".
  ///
  /// `MagazzinoDto` documents only `Sede` and `Furgone`; any other value is treated as a Sede
  /// (principale), so grouping and filtering share the same `isFurgone` predicate.
  String? get tipo => switch (this) {
    _MagazzinoStatusFilter.tutti => null,
    _MagazzinoStatusFilter.principali => 'Sede',
    _MagazzinoStatusFilter.secondari => 'Furgone',
  };

  bool matches(MagazzinoDto magazzino) => switch (this) {
    _MagazzinoStatusFilter.tutti => true,
    _MagazzinoStatusFilter.principali => !magazzino.isFurgone,
    _MagazzinoStatusFilter.secondari => magazzino.isFurgone,
  };
}

/// The applied quick preset. Search text lives on the screen state beside it.
class _MagazzinoFilters {
  const _MagazzinoFilters({this.status = _MagazzinoStatusFilter.tutti});

  final _MagazzinoStatusFilter status;

  bool get isActive => status != _MagazzinoStatusFilter.tutti;
}

class AdminMagazzinoListScreen extends ConsumerStatefulWidget {
  const AdminMagazzinoListScreen({super.key});

  @override
  ConsumerState<AdminMagazzinoListScreen> createState() => _AdminMagazzinoListScreenState();
}

class _AdminMagazzinoListScreenState extends ConsumerState<AdminMagazzinoListScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  _MagazzinoFilters _filters = const _MagazzinoFilters();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _selectStatus(ListFilterChipData chip) {
    final status = _MagazzinoStatusFilter.values.firstWhere(
      (f) => f.id == chip.id,
      orElse: () => _MagazzinoStatusFilter.tutti,
    );
    setState(() => _filters = _MagazzinoFilters(status: status));
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<_MagazzinoFilters>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRack.cellRadius)),
      ),
      builder: (_) => _MagazzinoFilterSheet(initial: _filters),
    );
    if (result != null && mounted) setState(() => _filters = result);
  }

  Future<void> _refresh() async {
    ref.invalidate(magazziniProvider);
    try {
      await ref.read(magazziniProvider.future);
    } catch (_) {
      // A failed refresh after the first load keeps the rows the technician can already read.
      // `build` surfaces that as a stale-data banner; letting the error escape would instead be an
      // uncaught RefreshIndicator failure (and Sentry noise).
    }
  }

  @override
  Widget build(BuildContext context) {
    final magazziniAsync = ref.watch(magazziniProvider);
    final allMagazzini = magazziniAsync.valueOrNull ?? const <MagazzinoDto>[];
    final colleaguesById = {
      for (final c in ref.watch(allColleaguesProvider).valueOrNull ?? const <Colleague>[])
        c.id: c.displayName,
    };

    final search = _query.trim().toLowerCase();
    final filtered =
        allMagazzini.where((m) {
          if (!_filters.status.matches(m)) return false;
          if (search.isEmpty) return true;
          final assignee = m.assegnatoUserId == null ? null : colleaguesById[m.assegnatoUserId];
          return m.nome.toLowerCase().contains(search) ||
              m.tipo.toLowerCase().contains(search) ||
              (m.indirizzo?.toLowerCase().contains(search) ?? false) ||
              (assignee?.toLowerCase().contains(search) ?? false);
        }).toList()..sort((a, b) {
          final an = a.nome.toLowerCase();
          final bn = b.nome.toLowerCase();
          return an.compareTo(bn);
        });

    final principali = filtered.where((m) => !m.isFurgone).toList();
    final secondari = filtered.where((m) => m.isFurgone).toList();
    final groups = [
      if (principali.isNotEmpty)
        ListGroupData(
          title: 'Principali',
          count: principali.length,
          rows: [for (final m in principali) _rowFor(context, m, colleaguesById)],
        ),
      if (secondari.isNotEmpty)
        ListGroupData(
          title: 'Secondari',
          count: secondari.length,
          rows: [for (final m in secondari) _rowFor(context, m, colleaguesById)],
        ),
    ];

    final activeCount = filtered.where((m) => m.isActive).length;
    final hasActiveFilter = search.isNotEmpty || _filters.isActive;
    final canCreate =
        ref
            .watch(cachedEntitlementProvider)
            .value
            ?.capabilities
            .contains('magazzino.warehouse.write') ??
        false;

    final isLoading =
        magazziniAsync.isLoading && !magazziniAsync.hasValue && !magazziniAsync.hasError;
    final isUnavailable = magazziniAsync.hasError && !magazziniAsync.hasValue;
    // A refresh that failed after the first successful read keeps the previous rows; without this
    // line they would look current. The first-load failure still takes the `ErrorState` branch.
    final isStale = magazziniAsync.hasError && magazziniAsync.hasValue;

    Widget unavailable() => magazziniAsync.error is MagazziniOfflineException
        ? const UnavailableState(
            icon: LucideIcons.warehouse,
            titolo: 'Magazzini non disponibili offline',
            motivo:
                'Questo dispositivo non ha ancora scaricato i magazzini. Apri '
                'questa lista con una connessione attiva per averli anche offline.',
          )
        : ErrorState(onRetry: () => ref.invalidate(magazziniProvider));

    Widget empty() {
      final typed = _query.trim();
      if (hasActiveFilter) {
        return EmptyState(
          icon: LucideIcons.searchX,
          title: 'Nessun risultato',
          body: typed.isNotEmpty
              ? 'Nessun magazzino corrisponde a "$typed".'
              : 'Nessun magazzino corrisponde ai filtri selezionati.',
        );
      }
      return EmptyState(
        icon: LucideIcons.warehouse,
        title: 'Nessun magazzino',
        body: canCreate
            ? 'Non è ancora stato creato nessun magazzino. Usa Nuovo per crearne uno.'
            : 'Non è ancora stato creato nessun magazzino.',
      );
    }

    Widget framed(Widget child) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
          child: child,
        ),
      ),
    );

    Widget scrollable(Widget child) => RefreshIndicator(
      onRefresh: _refresh,
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

    final Widget content;
    if (isLoading) {
      content = scrollable(const ListLoadingSkeleton());
    } else if (isUnavailable) {
      content = scrollable(unavailable());
    } else if (groups.isEmpty) {
      content = scrollable(empty());
    } else {
      final summary = ListSummaryData(
        left: _magazziniLabel(filtered.length),
        right: '$activeCount ${activeCount == 1 ? 'attivo' : 'attivi'}',
      );
      content = RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            for (final group in groups) ...[
              SliverToBoxAdapter(
                child: framed(ListGroupHeader(title: group.title!, count: group.count)),
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
            SliverToBoxAdapter(child: framed(ListSummaryFooter(data: summary))),
            SliverToBoxAdapter(child: SizedBox(height: context.navClearance)),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: Column(
          children: [
            const OfflineSyncBanner(),
            ScreenHeader(
              title: 'Magazzini',
              subtitle: 'Dove sono le cose e cosa manca in ogni luogo.',
              subtitleMaxLines: 2,
              showBack: true,
              actions: [
                CapabilityGate(
                  capability: 'magazzino.warehouse.write',
                  child: ListHeaderAction(
                    label: 'Nuovo',
                    onPressed: () => context.push('/altro/magazzino/magazzini/nuovo'),
                  ),
                ),
              ],
            ),
            AppSearchBar(
              controller: _searchCtrl,
              hint: 'Cerca magazzino, tipo o indirizzo…',
              onChanged: (q) => setState(() => _query = q),
            ),
            ListFilterRow(
              filters: [
                for (final status in _MagazzinoStatusFilter.values)
                  ListFilterChipData(label: status.label, id: status.id),
              ],
              activeId: _filters.status.id,
              onSelected: _selectStatus,
              onOpenFilters: _openFilters,
            ),
            if (isStale)
              framed(
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: InlineAlert(
                    message:
                        'Impossibile aggiornare. I dati mostrati potrebbero non essere aggiornati.',
                    icon: LucideIcons.alertCircle,
                  ),
                ),
              ),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }

  ListRowData _rowFor(
    BuildContext context,
    MagazzinoDto magazzino,
    Map<String, String> colleaguesById,
  ) {
    final assignee = magazzino.assegnatoUserId == null
        ? null
        : colleaguesById[magazzino.assegnatoUserId];
    final place = magazzino.isFurgone
        ? (assignee == null ? null : 'Assegnato a $assignee')
        : _text(magazzino.indirizzo);

    final (status, tone) = !magazzino.isActive
        ? ('Inattivo', ListStatusTone.bad)
        : magazzino.isFurgone
        ? ('Secondario', ListStatusTone.info)
        : ('Principale', ListStatusTone.good);

    return ListRowData(
      title: _text(magazzino.nome) ?? 'Senza nome',
      meta: place,
      status: status,
      statusTone: tone,
      rowKey: ValueKey('magazzino-row-${magazzino.id}'),
      onTap: () => context.push('/altro/magazzino/magazzini/${magazzino.id}', extra: magazzino),
    );
  }

  static String _magazziniLabel(int count) => count == 1 ? '1 magazzino' : '$count magazzini';

  static String? _text(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

// ── Filter sheet ────────────────────────────────────────────────────────────

class _MagazzinoFilterSheet extends StatefulWidget {
  const _MagazzinoFilterSheet({required this.initial});

  final _MagazzinoFilters initial;

  @override
  State<_MagazzinoFilterSheet> createState() => _MagazzinoFilterSheetState();
}

class _MagazzinoFilterSheetState extends State<_MagazzinoFilterSheet> {
  late _MagazzinoStatusFilter _status = widget.initial.status;

  /// The prototype has both `Stato` chips and a `Tipo` field, but this DTO's only type field is
  /// `Sede`/`Furgone` — the same two groups. The two controls therefore express one facet, kept in
  /// sync so the sheet can never leave a contradiction behind (e.g. `Principali` + `Furgone`).
  String? get _tipoValue => _status.tipo;

  void _selectStatus(_MagazzinoStatusFilter status) {
    setState(() => _status = status);
  }

  void _selectTipo(String? tipo) {
    setState(() {
      _status = switch (tipo) {
        'Sede' => _MagazzinoStatusFilter.principali,
        'Furgone' => _MagazzinoStatusFilter.secondari,
        _ => _MagazzinoStatusFilter.tutti,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

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
              child: Center(child: SheetHandle()),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    'Filtri',
                    style: AppTextStyles.headlineLarge.copyWith(color: colors.ink),
                  ),
                ),
                Text(
                  'MAGAZZINI',
                  style: AppTextStyles.docCode.copyWith(
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: colors.accentInk,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Restringi per stato e tipo. Nessun identificativo interno.',
              style: AppTextStyles.caption.copyWith(color: colors.inkMuted),
            ),
            const SizedBox(height: 16),
            const AppFieldLabel(label: 'Stato', enabled: true),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final status in _MagazzinoStatusFilter.values)
                  _MagazzinoFilterChoice(
                    key: ValueKey('magazziniFilterStatus-${status.id}'),
                    label: status.label,
                    active: _status == status,
                    onTap: () => _selectStatus(status),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            AppFieldShell(
              label: 'Tipo',
              child: DropdownButtonFormField<String?>(
                key: const Key('magazziniFilterTipo'),
                // Controlled field: it must follow the status chips, so `initialValue` (first
                // build only) would go stale.
                // ignore: deprecated_member_use
                value: _tipoValue,
                isExpanded: true,
                decoration: _sheetFieldDecoration(context),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Tutti i tipi')),
                  DropdownMenuItem(value: 'Sede', child: Text('Sede')),
                  DropdownMenuItem(value: 'Furgone', child: Text('Furgone')),
                ],
                onChanged: _selectTipo,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: AppButton.ghost(
                    key: const Key('magazziniFilterReset'),
                    label: 'Azzera',
                    onPressed: () => Navigator.pop(context, const _MagazzinoFilters()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    key: const Key('magazziniFilterApply'),
                    label: 'Applica filtri',
                    onPressed: () => Navigator.pop(context, _MagazzinoFilters(status: _status)),
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

InputDecoration _sheetFieldDecoration(BuildContext context) => InputDecoration(
  isDense: true,
  filled: true,
  fillColor: context.colors.bg2,
  contentPadding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
  border: OutlineInputBorder(
    borderRadius: AppRack.freeShape,
    borderSide: BorderSide(color: context.colors.borderLight),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: AppRack.freeShape,
    borderSide: BorderSide(color: context.colors.borderLight),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: AppRack.freeShape,
    borderSide: BorderSide(color: context.colors.ink),
  ),
);

class _MagazzinoFilterChoice extends StatelessWidget {
  const _MagazzinoFilterChoice({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
  });

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
      onTap: onTap,
      excludeSemantics: true,
      child: AppTappable(
        onTap: onTap,
        borderRadius: AppRack.freeShape,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: active ? colors.ink : colors.surface,
                borderRadius: AppRack.freeShape,
                border: Border.all(color: active ? colors.ink : colors.borderLight),
              ),
              child: Padding(
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
        ),
      ),
    );
  }
}
