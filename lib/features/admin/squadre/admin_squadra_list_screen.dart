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
import '../../../data/sync/connectivity_provider.dart';
import '../../../data/users/user_directory.dart';
import '../admin_api_client.dart';

/// Fetches squadre from backend API.
final adminSquadreProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final api = ref.watch(adminApiClientProvider);
  return api.fetchSquadre();
});

/// Per-squadra member counts come from the shared [allUsersProvider] (active users) — one bulk
/// fetch rather than one per squadra or per member. See
/// [AdminApiClient.fetchAllUsersWithSquadraInfo]'s doc comment for why.

/// The status presets from the prototype's Squadre chip row.
enum _SquadraStatusFilter { attive, tutte, inattive }

extension on _SquadraStatusFilter {
  String get id => name;

  String get label => switch (this) {
    _SquadraStatusFilter.attive => 'Attive',
    _SquadraStatusFilter.tutte => 'Tutte',
    _SquadraStatusFilter.inattive => 'Inattive',
  };

  bool matches(bool isActive) => switch (this) {
    _SquadraStatusFilter.attive => isActive,
    _SquadraStatusFilter.tutte => true,
    _SquadraStatusFilter.inattive => !isActive,
  };
}

/// The quick chip plus every facet reachable from the `Filtri` sheet.
///
/// Cantiere and `Solo con cantieri` are deliberately absent: neither `/api/squadre` nor the
/// `/api/users` projection carries a cantiere association, and inventing one would need a new
/// network read (see the report's DROPPED FACTS / PROPOSALS).
class _SquadraFilters {
  const _SquadraFilters({this.status = _SquadraStatusFilter.tutte, this.lead});

  final _SquadraStatusFilter status;

  /// Matched against the server-derived `capSquadraNome`.
  final String? lead;

  bool get hasFacets => lead != null;

  /// Drops a lead whose squadra was deactivated or renamed while the sheet was open, so the list
  /// does not silently filter on a value the sheet can no longer show.
  _SquadraFilters reconciled({required bool Function(String lead) hasLead}) {
    final selected = lead;
    return _SquadraFilters(
      status: status,
      lead: selected != null && hasLead(selected) ? selected : null,
    );
  }

  _SquadraFilters copyWith({_SquadraStatusFilter? status, String? lead, bool clearLead = false}) {
    return _SquadraFilters(
      status: status ?? this.status,
      lead: clearLead ? null : (lead ?? this.lead),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _SquadraFilters && other.status == status && other.lead == lead;

  @override
  int get hashCode => Object.hash(status, lead);
}

/// Admin squadra list — online-only (squadre are not in the sync payload).
class AdminSquadraListScreen extends ConsumerStatefulWidget {
  const AdminSquadraListScreen({super.key});

  @override
  ConsumerState<AdminSquadraListScreen> createState() => _AdminSquadraListScreenState();
}

class _AdminSquadraListScreenState extends ConsumerState<AdminSquadraListScreen> {
  String _query = '';
  final _searchCtrl = TextEditingController();
  _SquadraFilters _filters = const _SquadraFilters();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _selectStatus(ListFilterChipData chip) {
    final status = _SquadraStatusFilter.values.firstWhere(
      (f) => f.id == chip.id,
      orElse: () => _SquadraStatusFilter.tutte,
    );
    setState(() => _filters = _filters.copyWith(status: status));
  }

  Future<void> _openFilterSheet({required List<String> leads}) async {
    final reconciled = _filters.reconciled(hasLead: leads.contains);
    if (reconciled != _filters && mounted) setState(() => _filters = reconciled);

    final result = await showModalBottomSheet<_SquadraFilters>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRack.cellRadius)),
      ),
      builder: (_) => _SquadraFilterSheet(initial: reconciled, leads: leads),
    );
    if (result != null && mounted) setState(() => _filters = result);
  }

  @override
  Widget build(BuildContext context) {
    final squadreAsync = ref.watch(adminSquadreProvider);
    // Only ask for the member projection once the squadre are actually here: a failed or still
    // loading list cannot use it, and firing it alongside every error would be a wasted read.
    final users = squadreAsync.hasValue
        ? ref.watch(allUsersProvider(true)).value ?? const []
        : const <Map<String, dynamic>>[];

    // One bulk fetch for the whole list, not one per row. `squadraId` is the derived field
    // UsersController.PopulateSquadreAsync projects onto every user response.
    final memberCounts = <String, int>{};
    final memberNames = <String, List<String>>{};
    for (final u in users) {
      final squadraId = u['squadraId'] as String?;
      if (squadraId == null) continue;
      memberCounts[squadraId] = (memberCounts[squadraId] ?? 0) + 1;
      memberNames.putIfAbsent(squadraId, () => []).add(userDisplayName(u));
    }

    final rows = squadreAsync.value ?? const <Map<String, dynamic>>[];
    final leads = <String>{
      for (final s in rows)
        if (_text(s['capSquadraNome']) != null) _text(s['capSquadraNome'])!,
    }.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final filters = _filters.reconciled(hasLead: leads.contains);
    final hasActiveFilter =
        _query.trim().isNotEmpty ||
        filters.hasFacets ||
        filters.status != _SquadraStatusFilter.tutte;
    final isLoading = squadreAsync.isLoading && !squadreAsync.hasValue && !squadreAsync.hasError;
    final state = squadreAsync.hasError
        ? ListShellState.unavailable
        : isLoading
        ? ListShellState.loading
        : ListShellState.content;
    final activeCount = rows.where((s) => s['isActive'] as bool? ?? true).length;
    final groups = state == ListShellState.content
        ? _groups(
            rows: rows,
            memberCounts: memberCounts,
            memberNames: memberNames,
            filters: filters,
          )
        : const <ListGroupData>[];

    return ListShell(
      title: 'Squadre',
      subtitle: 'Chi lavora insieme e su quali cantieri.',
      showBack: true,
      searchHint: 'Cerca squadra, lead o membro…',
      searchController: _searchCtrl,
      onSearchChanged: (q) => setState(() => _query = q),
      filters: const [
        ListFilterChipData(label: 'Attive', id: 'attive'),
        ListFilterChipData(label: 'Tutte', id: 'tutte'),
        ListFilterChipData(label: 'Inattive', id: 'inattive'),
      ],
      activeFilterId: filters.status.id,
      onFilterSelected: _selectStatus,
      onOpenFilters: () => _openFilterSheet(leads: leads),
      action: CapabilityGate(
        capability: 'team.squadra.write',
        child: ListHeaderAction(
          label: 'Nuovo',
          onPressed: () => context.push('/altro/squadre/nuovo'),
        ),
      ),
      groups: groups,
      summary: groups.isEmpty
          ? null
          : ListSummaryData(left: _squadreLabel(rows.length), right: '$activeCount attive'),
      state: state,
      empty: _emptyState(hasActiveFilter: hasActiveFilter),
      // Offline is not a failure: nothing was attempted, and retrying cannot help until the radio
      // is back. The red "Impossibile caricare i dati" card would read as "your squadre may be
      // gone", which is the one thing this screen cannot know.
      unavailable: !ref.watch(isOnlineProvider)
          ? UnavailableState(
              icon: LucideIcons.wifiOff,
              titolo: 'Squadre non disponibili offline',
              motivo:
                  'Le squadre si leggono con la connessione: non vengono scaricate '
                  'sul dispositivo.',
              action: AppButton(
                label: 'Riprova',
                size: AppButtonSize.sm,
                fullWidth: false,
                onPressed: () => ref.invalidate(adminSquadreProvider),
              ),
            )
          : ErrorState(onRetry: () => ref.invalidate(adminSquadreProvider)),
      onRefresh: () => ref.refresh(adminSquadreProvider.future),
    );
  }

  List<ListGroupData> _groups({
    required List<Map<String, dynamic>> rows,
    required Map<String, int> memberCounts,
    required Map<String, List<String>> memberNames,
    required _SquadraFilters filters,
  }) {
    final q = _query.trim().toLowerCase();
    final filtered = rows.where((s) {
      final id = s['id'] as String? ?? '';
      final isActive = s['isActive'] as bool? ?? true;
      if (!filters.status.matches(isActive)) return false;
      final lead = _text(s['capSquadraNome']);
      if (filters.lead != null && lead != filters.lead) return false;
      if (q.isEmpty) return true;
      final nome = _text(s['nome'])?.toLowerCase() ?? '';
      final specializzazione = _text(s['specializzazione'])?.toLowerCase() ?? '';
      return nome.contains(q) ||
          (lead?.toLowerCase().contains(q) ?? false) ||
          specializzazione.contains(q) ||
          (memberNames[id]?.any((name) => name.toLowerCase().contains(q)) ?? false);
    }).toList();

    return <ListGroupData>[
      for (final (title, isActive) in const [('Attive', true), ('Inattive', false)])
        if (filtered.any((s) => (s['isActive'] as bool? ?? true) == isActive))
          ListGroupData(
            title: title,
            count: filtered.where((s) => (s['isActive'] as bool? ?? true) == isActive).length,
            rows: [
              for (final s in filtered.where((s) => (s['isActive'] as bool? ?? true) == isActive))
                _rowData(context, s, memberCounts[s['id'] as String? ?? ''] ?? 0),
            ],
          ),
    ];
  }

  Widget _emptyState({required bool hasActiveFilter}) {
    if (hasActiveFilter) {
      return EmptyState(
        icon: LucideIcons.searchX,
        title: 'Nessun risultato',
        body: _query.trim().isNotEmpty
            ? 'Nessuna squadra corrisponde a "${_query.trim()}".'
            : 'Nessuna squadra corrisponde ai filtri selezionati.',
      );
    }
    return const EmptyState(
      icon: LucideIcons.users,
      title: 'Nessuna squadra',
      body: 'Crea una nuova squadra con il pulsante Nuovo.',
    );
  }

  static ListRowData _rowData(BuildContext context, Map<String, dynamic> squadra, int memberCount) {
    final id = squadra['id'] as String? ?? '';
    final lead = _text(squadra['capSquadraNome']);
    final specializzazione = _text(squadra['specializzazione']);
    final isActive = squadra['isActive'] as bool? ?? true;

    return ListRowData(
      title: _text(squadra['nome']) ?? 'Squadra senza nome',
      meta: [if (lead != null) 'Lead $lead', _membriLabel(memberCount)].join(' · '),
      // The prototype's third line is the active-cantiere count; the API does not carry one, so
      // the squadra's own specializzazione keeps the line useful instead of inventing a number.
      secondary: specializzazione,
      status: isActive ? 'Attiva' : 'Inattiva',
      statusTone: isActive ? ListStatusTone.good : ListStatusTone.bad,
      onTap: () => context.push('/altro/squadre/$id', extra: squadra),
      rowKey: ValueKey('squadra-row-$id'),
    );
  }

  static String _membriLabel(int count) => count == 1 ? '1 membro' : '$count membri';

  static String _squadreLabel(int count) => count == 1 ? '1 squadra' : '$count squadre';

  static String? _text(Object? value) {
    final text = value is String ? value.trim() : null;
    return text == null || text.isEmpty ? null : text;
  }
}

class _SquadraFilterSheet extends StatefulWidget {
  const _SquadraFilterSheet({required this.initial, required this.leads});

  final _SquadraFilters initial;
  final List<String> leads;

  @override
  State<_SquadraFilterSheet> createState() => _SquadraFilterSheetState();
}

class _SquadraFilterSheetState extends State<_SquadraFilterSheet> {
  late _SquadraFilters _draft = widget.initial;

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
              child: SheetHandle(),
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
                  'SQUADRE',
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
              'Restringi per stato e lead.',
              style: AppTextStyles.caption.copyWith(color: colors.inkMuted),
            ),
            const SizedBox(height: 16),
            _SquadraSheetField(
              label: 'Stato',
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final status in _SquadraStatusFilter.values)
                    _SquadraFilterChoice(
                      key: ValueKey('squadreFilterStatus-${status.id}'),
                      label: status.label,
                      active: _draft.status == status,
                      onTap: () => setState(() => _draft = _draft.copyWith(status: status)),
                    ),
                ],
              ),
            ),
            if (widget.leads.isNotEmpty) ...[
              const SizedBox(height: 16),
              _SquadraSheetField(
                label: 'Lead',
                child: Semantics(
                  label: 'Lead',
                  container: true,
                  child: DropdownButtonFormField<String?>(
                    key: const Key('squadreFilterLead'),
                    initialValue: widget.leads.contains(_draft.lead) ? _draft.lead : null,
                    isExpanded: true,
                    decoration: _sheetFieldDecoration(context),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Tutti')),
                      for (final lead in widget.leads)
                        DropdownMenuItem(value: lead, child: Text(lead)),
                    ],
                    onChanged: (v) => setState(() {
                      _draft = v == null
                          ? _draft.copyWith(clearLead: true)
                          : _draft.copyWith(lead: v);
                    }),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: AppButton.ghost(
                    key: const Key('squadreFilterReset'),
                    label: 'Azzera',
                    onPressed: () => Navigator.pop(context, const _SquadraFilters()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    key: const Key('squadreFilterApply'),
                    label: 'Applica filtri',
                    onPressed: () => Navigator.pop(context, _draft),
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

/// The prototype's mono micro-label above a sheet field (`.filter-label`).
class _SquadraSheetField extends StatelessWidget {
  const _SquadraSheetField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: AppTextStyles.docCode.copyWith(
            fontSize: 7.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
            color: context.colors.inkMuted,
          ),
        ),
        const SizedBox(height: 5),
        child,
      ],
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

class _SquadraFilterChoice extends StatelessWidget {
  const _SquadraFilterChoice({
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
    final chip = DecoratedBox(
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
    );

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
          child: Center(widthFactor: 1, heightFactor: 1, child: chip),
        ),
      ),
    );
  }
}
