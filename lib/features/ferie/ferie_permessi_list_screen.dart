// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_rack.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';
import 'package:tasktap_mobile/core/theme/app_text_styles.dart';

import '../../core/utils/offline_guard.dart';
import '../../core/widgets/widgets.dart';
import '../../data/ferie/absence_request_api_client.dart';
import '../../data/sync/sync_freshness_provider.dart' show hasSyncedAtLeastOnceProvider;
import '../../presentation/providers/auth_providers.dart' show internalUserIdProvider;
import '../../presentation/providers/schedule_providers.dart' show colleagueNameProvider;

const Set<int> _kCancellable = {0, 1}; // Pending, Approved

/// Which absence states the list is showing. Mirrors the prototype's quick chips; [annullate] is
/// the existing cancelled state, kept reachable through the `Filtri` sheet so no row disappears.
enum _FerieStatusFilter { tutte, inAttesa, approvate, respinte, annullate }

extension on _FerieStatusFilter {
  String get label => switch (this) {
    _FerieStatusFilter.tutte => 'Tutte',
    _FerieStatusFilter.inAttesa => 'In attesa',
    _FerieStatusFilter.approvate => 'Approvate',
    _FerieStatusFilter.respinte => 'Respinte',
    _FerieStatusFilter.annullate => 'Annullate',
  };

  int? get status => switch (this) {
    _FerieStatusFilter.tutte => null,
    _FerieStatusFilter.inAttesa => 0,
    _FerieStatusFilter.approvate => 1,
    _FerieStatusFilter.respinte => 2,
    _FerieStatusFilter.annullate => 3,
  };
}

/// The prototype's `Tipo` facet: Ferie (0) and the permesso family (legacy 1, retribuito 5,
/// non retribuito 6). Every other type (malattia, ROL, …) stays reachable under `Tutti`.
enum _FerieTypeFilter { tutti, ferie, permesso }

extension on _FerieTypeFilter {
  String get label => switch (this) {
    _FerieTypeFilter.tutti => 'Tutti',
    _FerieTypeFilter.ferie => 'Ferie',
    _FerieTypeFilter.permesso => 'Permesso',
  };

  bool matches(int type) => switch (this) {
    _FerieTypeFilter.tutti => true,
    _FerieTypeFilter.ferie => type == 0,
    _FerieTypeFilter.permesso => kPermessoAbsenceTypes.contains(type),
  };
}

class _FerieFilters {
  const _FerieFilters({
    this.status = _FerieStatusFilter.tutte,
    this.type = _FerieTypeFilter.tutti,
    this.from,
    this.to,
  });

  final _FerieStatusFilter status;
  final _FerieTypeFilter type;
  final DateTime? from;
  final DateTime? to;

  bool matchesStatus(int value) => status.status == null || status.status == value;

  bool matchesPeriod(AbsenceRequestDto item) {
    if (from == null && to == null) return true;
    final start = DateUtils.dateOnly(from ?? DateTime(1970));
    final end = DateUtils.dateOnly(to ?? DateTime(2100));
    final itemStart = DateUtils.dateOnly(item.startDate);
    final itemEnd = DateUtils.dateOnly(item.endDate);
    return !itemStart.isAfter(end) && !itemEnd.isBefore(start);
  }
}

/// Self-service AbsenceRequest history.
///
/// Reads the server when it can and the device's synced mirror when it cannot — "was my request
/// approved" was answered days ago and does not need a radio. Filing and cancelling stay online
/// (see AbsenceRequestApiClient's own file doc).
///
/// Rebuilt on the wave-0 list shell pieces: header (`Ferie e permessi`, subtitle, `Nuovo`) →
/// search → status chips + `Filtri` → `In attesa`/`Approvate`/`Respinte`/`Annullate` groups →
/// summary. The data source is the existing `myAbsenceRequestsProvider`: no new network read.
class FeriePermessiListScreen extends ConsumerStatefulWidget {
  const FeriePermessiListScreen({super.key});

  @override
  ConsumerState<FeriePermessiListScreen> createState() => _FeriePermessiListScreenState();
}

class _FeriePermessiListScreenState extends ConsumerState<FeriePermessiListScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  _FerieFilters _filters = const _FerieFilters();

  static const _chips = [
    ListFilterChipData(label: 'In attesa', id: 'in-attesa'),
    ListFilterChipData(label: 'Approvate', id: 'approvate'),
    ListFilterChipData(label: 'Respinte', id: 'respinte'),
    ListFilterChipData(label: 'Tutte', id: 'tutte'),
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String? get _activeChipId => switch (_filters.status) {
    _FerieStatusFilter.inAttesa => 'in-attesa',
    _FerieStatusFilter.approvate => 'approvate',
    _FerieStatusFilter.respinte => 'respinte',
    _FerieStatusFilter.tutte => 'tutte',
    _FerieStatusFilter.annullate => null,
  };

  void _selectChip(ListFilterChipData chip) {
    final status = switch (chip.id) {
      'in-attesa' => _FerieStatusFilter.inAttesa,
      'approvate' => _FerieStatusFilter.approvate,
      'respinte' => _FerieStatusFilter.respinte,
      _ => _FerieStatusFilter.tutte,
    };
    setState(
      () => _filters = _FerieFilters(
        status: status,
        type: _filters.type,
        from: _filters.from,
        to: _filters.to,
      ),
    );
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<_FerieFilters>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _FerieFilterSheet(initial: _filters),
    );
    if (result != null && mounted) setState(() => _filters = result);
  }

  @override
  Widget build(BuildContext context) {
    final requestsAsync = ref.watch(myAbsenceRequestsProvider);
    final meId = ref.watch(internalUserIdProvider).valueOrNull;
    final myName = meId == null ? null : ref.watch(colleagueNameProvider(meId)).valueOrNull;

    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: 'Ferie e permessi',
              subtitle: 'Le richieste del team e il loro stato.',
              subtitleMaxLines: 2,
              showBack: true,
              actions: [
                ListHeaderAction(
                  label: 'Nuovo',
                  onPressed: () => context.push('/altro/ferie/nuovo'),
                ),
              ],
            ),
            AppSearchBar(
              controller: _searchCtrl,
              hint: 'Cerca persona, tipo o periodo…',
              onChanged: (q) => setState(() => _query = q),
            ),
            ListFilterRow(
              filters: _chips,
              activeId: _activeChipId,
              onSelected: _selectChip,
              onOpenFilters: _openFilters,
            ),
            Expanded(
              child: _body(ref: ref, requestsAsync: requestsAsync, myName: myName),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body({
    required WidgetRef ref,
    required AsyncValue<MyAbsenceRequests> requestsAsync,
    required String? myName,
  }) {
    Future<void> onRefresh() => ref.refresh(myAbsenceRequestsProvider.future);

    if (requestsAsync.isLoading && !requestsAsync.hasValue) {
      return _scrollable(const ListLoadingSkeleton(), onRefresh);
    }

    if (requestsAsync.hasError && !requestsAsync.hasValue) {
      return _scrollable(
        ErrorState(onRetry: () => ref.invalidate(myAbsenceRequestsProvider)),
        onRefresh,
      );
    }

    final result =
        requestsAsync.valueOrNull ?? (items: const <AbsenceRequestDto>[], fromDevice: false);

    // An empty list from the mirror on a phone that has never synced is a missing download, not a
    // fact about the technician: saying "Nessuna richiesta" there would tell them their history
    // never existed. An empty list from the SERVER is such a fact.
    final neverSynced =
        result.fromDevice && ref.watch(hasSyncedAtLeastOnceProvider).valueOrNull == false;

    if (result.items.isEmpty) {
      if (neverSynced) {
        return _scrollable(
          UnavailableState(
            icon: LucideIcons.wifiOff,
            titolo: 'Richieste non ancora scaricate',
            motivo:
                'Nessuna copia delle tue richieste su questo dispositivo. Verrà scaricata '
                'alla prossima sincronizzazione.',
            action: AppButton(
              label: 'Riprova',
              size: AppButtonSize.sm,
              fullWidth: false,
              onPressed: () => ref.invalidate(myAbsenceRequestsProvider),
            ),
          ),
          onRefresh,
        );
      }
      return _scrollable(
        const EmptyState(
          icon: LucideIcons.calendarX,
          title: 'Nessuna richiesta',
          body: 'Invia una nuova richiesta con il pulsante Nuovo.',
        ),
        onRefresh,
      );
    }

    final visible = result.items.where((item) {
      if (!_filters.matchesStatus(item.status)) return false;
      if (!_filters.type.matches(item.type)) return false;
      if (!_filters.matchesPeriod(item)) return false;
      return _matchesQuery(item, myName);
    }).toList();

    if (visible.isEmpty) {
      return _scrollable(
        EmptyState(
          icon: LucideIcons.searchX,
          title: 'Nessun risultato',
          body: _query.isNotEmpty
              ? 'Nessuna richiesta corrisponde a "$_query".'
              : 'Nessuna richiesta corrisponde a ricerca e filtri attivi.',
        ),
        onRefresh,
      );
    }

    final groups = _groups(visible);
    final pending = visible.where((item) => item.status == 0).length;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          for (final group in groups) ...[
            SliverToBoxAdapter(
              child: _framed(
                child: ListGroupHeader(title: group.title, count: group.count),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => KeyedSubtree(
                    key: group.rows[i].rowKey,
                    child: _row(context, ref, group.rows[i].item, myName),
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
                  left: _requestsLabel(visible.length),
                  right: _pendingLabel(pending),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(child: SizedBox(height: context.navClearance)),
        ],
      ),
    );
  }

  List<_FerieGroup> _groups(List<AbsenceRequestDto> visible) {
    const titles = ['In attesa', 'Approvate', 'Respinte', 'Annullate'];
    final groups = <_FerieGroup>[];
    for (var status = 0; status < 4; status++) {
      final rows = visible.where((item) => item.status == status).toList();
      if (rows.isEmpty) continue;
      groups.add(
        _FerieGroup(
          title: titles[status],
          count: rows.length,
          rows: [
            for (final item in rows) _FerieRow(item: item, rowKey: ValueKey('ferie-${item.id}')),
          ],
        ),
      );
    }
    return groups;
  }

  Widget _row(BuildContext context, WidgetRef ref, AbsenceRequestDto item, String? myName) {
    final row = ListDocumentRow(data: _rowData(item, myName));
    if (!_kCancellable.contains(item.status)) return row;

    return Dismissible(
      key: ValueKey('ferie-${item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.xl),
        child: Icon(LucideIcons.x, color: context.colors.red),
      ),
      confirmDismiss: (_) => _confirmCancel(context, ref, item),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          row,
          _CancelAction(onCancel: () => _confirmCancel(context, ref, item)),
        ],
      ),
    );
  }

  ListRowData _rowData(AbsenceRequestDto item, String? myName) {
    return ListRowData(
      title: myName ?? 'Le mie richieste',
      meta: '${absenceTypeLabel(item.type)} · ${_periodLabel(item)}',
      secondary: '${_durationLabel(item)} · ${absenceStatusLabel(item.status).toLowerCase()}',
      status: absenceStatusLabel(item.status),
      statusTone: switch (item.status) {
        0 => ListStatusTone.warn,
        1 => ListStatusTone.good,
        2 => ListStatusTone.bad,
        _ => ListStatusTone.bad,
      },
    );
  }

  bool _matchesQuery(AbsenceRequestDto item, String? myName) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final haystack = [
      myName ?? '',
      absenceTypeLabel(item.type),
      _periodLabel(item),
      absenceStatusLabel(item.status),
      item.reason ?? '',
    ].join(' ').toLowerCase();
    return haystack.contains(q);
  }

  Widget _scrollable(Widget child, Future<void> Function() onRefresh) {
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
}

/// One group carrying its source rows so the list can render a custom row (with the cancel strip)
/// instead of flattening to [ListRowData] only.
class _FerieGroup {
  const _FerieGroup({required this.title, required this.count, required this.rows});

  final String title;
  final int count;
  final List<_FerieRow> rows;
}

class _FerieRow {
  const _FerieRow({required this.item, required this.rowKey});

  final AbsenceRequestDto item;
  final Key rowKey;
}

class _CancelAction extends StatelessWidget {
  const _CancelAction({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        onPressed: onCancel,
        icon: Icon(LucideIcons.x, size: 14, color: context.colors.inkMuted),
        label: Text(
          'Annulla',
          style: AppTextStyles.docCode.copyWith(
            fontSize: 8,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.32,
            color: context.colors.inkMuted,
          ),
        ),
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          foregroundColor: context.colors.inkMuted,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

class _FerieFilterSheet extends StatefulWidget {
  const _FerieFilterSheet({required this.initial});

  final _FerieFilters initial;

  @override
  State<_FerieFilterSheet> createState() => _FerieFilterSheetState();
}

class _FerieFilterSheetState extends State<_FerieFilterSheet> {
  late _FerieStatusFilter _status = widget.initial.status;
  late _FerieTypeFilter _type = widget.initial.type;
  late DateTime? _from = widget.initial.from;
  late DateTime? _to = widget.initial.to;

  Future<void> _pick({required bool from}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (from ? _from : _to) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (from) {
        _from = picked;
        if (_to != null && picked.isAfter(_to!)) _to = picked;
      } else {
        _to = picked;
        if (_from != null && picked.isBefore(_from!)) _from = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd/MM/yyyy');

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
            const SizedBox(height: 4),
            Text(
              'Restringi per stato, tipo e periodo.',
              style: AppTextStyles.bodySmall.copyWith(
                fontSize: 10.5,
                color: context.colors.inkMuted,
              ),
            ),
            const SizedBox(height: 16),
            AppFieldShell(
              label: 'Stato',
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final status in _FerieStatusFilter.values)
                    _FilterChoice(
                      key: Key('ferie-filter-status-${status.name}'),
                      label: status.label,
                      active: _status == status,
                      onTap: () => setState(() => _status = status),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppFieldShell(
              label: 'Tipo',
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final type in _FerieTypeFilter.values)
                    _FilterChoice(
                      key: Key('ferie-filter-type-${type.name}'),
                      label: type.label,
                      active: _type == type,
                      onTap: () => setState(() => _type = type),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppFieldShell(
              label: 'Periodo',
              child: Row(
                children: [
                  Expanded(
                    child: _DateField(
                      key: const Key('ferie-filter-from'),
                      label: 'Da',
                      value: _from == null ? 'Qualsiasi' : dateFmt.format(_from!),
                      onTap: () => _pick(from: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DateField(
                      key: const Key('ferie-filter-to'),
                      label: 'A',
                      value: _to == null ? 'Qualsiasi' : dateFmt.format(_to!),
                      onTap: () => _pick(from: false),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: AppButton.ghost(
                    key: const Key('ferie-filter-reset'),
                    label: 'Azzera',
                    onPressed: () => Navigator.pop(context, const _FerieFilters()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    key: const Key('ferie-filter-apply'),
                    label: 'Applica',
                    onPressed: () => Navigator.pop(
                      context,
                      _FerieFilters(status: _status, type: _type, from: _from, to: _to),
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

class _DateField extends StatelessWidget {
  const _DateField({super.key, required this.label, required this.value, required this.onTap});

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label: $value',
      excludeSemantics: true,
      child: AppTappable(
        onTap: onTap,
        borderRadius: AppRack.freeShape,
        color: context.colors.surface,
        border: Border.all(color: context.colors.borderLight),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label.toUpperCase(),
                style: AppTextStyles.docCode.copyWith(
                  fontSize: 7.5,
                  letterSpacing: 0.4,
                  color: context.colors.inkMuted,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodySmall.copyWith(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: context.colors.ink,
                ),
              ),
            ],
          ),
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

Future<bool> _confirmCancel(BuildContext context, WidgetRef ref, AbsenceRequestDto item) async {
  // Vetro chrome via the shared helper, not a hand-built AlertDialog — same as
  // rapportini_list_screen.dart's own delete confirmation.
  final confirmed = await confirmDeleteDialog(
    context,
    title: 'Annullare la richiesta?',
    message: 'La richiesta verrà annullata e non potrà più essere ripristinata.',
    confirmLabel: 'Annulla richiesta',
  );
  if (!confirmed) return false;
  if (!context.mounted) return false;

  // The sibling create flow (ferie_permessi_form_screen.dart's own _save) already guards its
  // write with this; cancelling one skipped it.
  if (!ensureOnlineOrWarn(context, ref)) return false;

  try {
    await ref.read(absenceRequestApiClientProvider).cancel(item.id);
    if (context.mounted) ref.invalidate(myAbsenceRequestsProvider);
    return true;
  } catch (e) {
    if (context.mounted) {
      showAppToast(
        context,
        message: 'Impossibile annullare la richiesta. Riprova.',
        tone: ToastTone.error,
      );
    }
    return false;
  }
}

String _periodLabel(AbsenceRequestDto item) {
  final start = DateUtils.dateOnly(item.startDate);
  final end = DateUtils.dateOnly(item.endDate);
  final day = DateFormat('dd/MM', 'it');
  if (start == end) return day.format(start);
  if (start.year == end.year && start.month == end.month) {
    return '${DateFormat('dd', 'it').format(start)}–${day.format(end)}';
  }
  if (start.year == end.year) return '${day.format(start)}–${day.format(end)}';
  final full = DateFormat('dd/MM/yy', 'it');
  return '${full.format(start)}–${full.format(end)}';
}

String _durationLabel(AbsenceRequestDto item) {
  final startTime = item.startTime;
  final endTime = item.endTime;
  if (startTime != null && endTime != null) {
    final start = _parseTimeMinutes(startTime);
    final end = _parseTimeMinutes(endTime);
    if (start != null && end != null && end > start) {
      final minutes = end - start;
      if (minutes < 60) return '$minutes min';
      final hours = minutes / 60;
      final text = hours == hours.roundToDouble()
          ? '${hours.round()}'
          : hours.toStringAsFixed(1).replaceAll('.', ',');
      return hours == 1 ? '1 ora' : '$text ore';
    }
  }
  final days =
      DateUtils.dateOnly(item.endDate).difference(DateUtils.dateOnly(item.startDate)).inDays + 1;
  return days == 1 ? '1 giorno' : '$days giorni';
}

int? _parseTimeMinutes(String value) {
  final parts = value.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

String _requestsLabel(int count) => count == 1 ? '1 richiesta' : '$count richieste';

String _pendingLabel(int count) => count == 1 ? '1 in attesa' : '$count in attesa';
