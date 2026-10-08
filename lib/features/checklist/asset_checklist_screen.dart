// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

import '../../core/widgets/widgets.dart';
import '../../data/sync/connectivity_provider.dart';
import '../../domain/checklist/checklist_items.dart';
import '../../domain/checklist/checklist_models.dart';
import '../../domain/checklist/control_answer_rules.dart';
import '../../presentation/providers/report_editor_providers.dart';
import 'bulk_action_sheet.dart';
import 'checklist_providers.dart';
import 'editable_control_tile.dart';

/// Full-screen asset checklist: libretti, their children, and each asset's rows.
///
/// A route of its own, not a compartment sheet: the sheet wraps its content in a
/// `SingleChildScrollView`, so a lazy list inside it would still be laid out in full. With 200
/// children x 15 controls that is 3000 rows. Here a `CustomScrollView` over a flat item list builds
/// only what is on screen.
///
/// Focusing an asset (`focusAssetId`) expands it and opens the list on the "Obbligatori mancanti"
/// filter: lazy slivers have no known offsets to scroll to, and that filter reduces the list to the
/// offenders.
class AssetChecklistScreen extends ConsumerStatefulWidget {
  /// Exactly one of [ticketId] (read-only, from the ticket detail) or [reportId] (editable, from a
  /// rapportino; the ticket is the report's).
  const AssetChecklistScreen({
    super.key,
    this.ticketId,
    this.reportId,
    this.focusAssetId,
    this.initialFilter = ChecklistFilter.all,
  }) : assert(
         (ticketId != null) != (reportId != null),
         'pass either a ticket (read-only) or a report (editable)',
       );

  final String? ticketId;
  final String? reportId;
  final String? focusAssetId;
  final ChecklistFilter initialFilter;

  @override
  ConsumerState<AssetChecklistScreen> createState() => _AssetChecklistScreenState();
}

class _AssetChecklistScreenState extends ConsumerState<AssetChecklistScreen> {
  late ChecklistQuery _query = ChecklistQuery(
    filter: widget.initialFilter,
    expandedAssetIds: {if (widget.focusAssetId != null) widget.focusAssetId!},
  );
  final _search = TextEditingController();

  /// The answers as they were when the filter/search/layout was last applied. Filters decide
  /// membership from THIS, so a row answered under "Da compilare" stays under the thumb instead of
  /// vanishing after the first keystroke; header progress reads the live answers.
  late Map<String, ChecklistAnswer> _frozen = Map.of(_readLive());

  Map<String, ChecklistAnswer> _readLive() => widget.reportId == null
      ? const <String, ChecklistAnswer>{}
      : ref.read(controlAnswersProvider(widget.reportId!));

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _apply(ChecklistQuery q) => setState(() {
    _query = q;
    _frozen = Map.of(_readLive());
  });

  void _toggle(String assetId) {
    final next = {..._query.expandedAssetIds};
    if (!next.remove(assetId)) next.add(assetId);
    setState(() => _query = _query.copyWith(expandedAssetIds: next));
  }

  TicketChecklist? _lastTree;
  Set<String> _lastShown = const {};

  void _openBulk() {
    final tree = _lastTree;
    final reportId = widget.reportId;
    if (tree == null || reportId == null || _lastShown.isEmpty) return;
    showBulkActionSheet(context, reportId: reportId, tree: tree, scopeAssetIds: _lastShown);
  }

  @override
  Widget build(BuildContext context) {
    final reportId = widget.reportId;
    final ticketId =
        widget.ticketId ?? ref.watch(reportEditorProvider(reportId!).select((s) => s.ticketId));
    return Scaffold(
      backgroundColor: context.colors.bg2,
      appBar: ScreenHeaderBar(
        title: 'Controlli per asset',
        actions: [
          if (widget.reportId != null)
            HeaderIconBtn(
              icon: LucideIcons.checkCircle2,
              label: 'Azioni in blocco',
              onTap: _openBulk,
            ),
        ],
      ),
      body: (ticketId == null || ticketId.isEmpty)
          ? const EmptyState(
              icon: LucideIcons.clipboardCheck,
              title: 'Nessun ticket',
              body: 'Questo rapportino non è collegato a un ticket: non ci sono controlli per asset.',
            )
          : ref
                .watch(ticketChecklistProvider(ticketId))
                .when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (_, _) => const UnavailableState(
                    titolo: 'Checklist non leggibile',
                    motivo: 'I dati salvati sul telefono non si aprono. Torna indietro e riprova.',
                  ),
                  data: (tree) => _body(tree, ticketId),
                ),
    );
  }

  Widget _body(TicketChecklist tree, String ticketId) {
    final live = widget.reportId == null
        ? const <String, ChecklistAnswer>{}
        : ref.watch(controlAnswersProvider(widget.reportId!));
    final items = buildChecklistItems(
      tree,
      _query,
      (id) => _frozen[id],
      liveProgress: (id) => live[id],
    );
    _lastTree = tree;
    _lastShown = {
      for (final i in items)
        if (i is AssetHeaderItem) i.asset.assetId else if (i is ControlItem) i.asset.assetId,
    };
    return Column(
      children: [
        if (tree.omitted) _OmittedBanner(ticketId: ticketId),
        AppSearchBar(
          controller: _search,
          hint: _query.layout == ChecklistLayout.byAsset
              ? 'Cerca asset o matricola…'
              : 'Cerca controllo o asset…',
          onChanged: (t) => _apply(_query.copyWith(text: t)),
        ),
        _FilterBar(query: _query, onChanged: _apply),
        Expanded(
          child: items.isEmpty
              ? EmptyState(
                  icon: LucideIcons.clipboardCheck,
                  title: 'Nessun elemento',
                  body: _query.filter == ChecklistFilter.all && _query.text.isEmpty
                      ? 'Questo ticket non ha asset con una checklist.'
                      : 'Nessun asset corrisponde ai filtri scelti.',
                )
              : CustomScrollView(
                  slivers: [
                    SliverList.builder(
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final item = items[i];
                        return KeyedSubtree(
                          key: ValueKey(item.key),
                          child: _ItemView(
                            item: item,
                            reportId: widget.reportId,
                            live: live,
                            onToggle: _toggle,
                            showAssetName: _query.layout == ChecklistLayout.byControl,
                          ),
                        );
                      },
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
                  ],
                ),
        ),
      ],
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.query, required this.onChanged});

  final ChecklistQuery query;
  final ValueChanged<ChecklistQuery> onChanged;

  @override
  Widget build(BuildContext context) {
    const filters = {
      ChecklistFilter.all: 'Tutti',
      ChecklistFilter.toFill: 'Da compilare',
      ChecklistFilter.requiredMissing: 'Obbligatori mancanti',
      ChecklistFilter.exceptions: 'Eccezioni',
    };
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
        children: [
          for (final e in filters.entries)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: ChoiceChip(
                label: Text(e.value),
                selected: query.filter == e.key,
                onSelected: (_) => onChanged(query.copyWith(filter: e.key)),
              ),
            ),
          const SizedBox(width: AppSpacing.md),
          for (final layout in ChecklistLayout.values)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: ChoiceChip(
                label: Text(layout == ChecklistLayout.byAsset ? 'Per asset' : 'Per controllo'),
                selected: query.layout == layout,
                onSelected: (_) => onChanged(query.copyWith(layout: layout)),
              ),
            ),
        ],
      ),
    );
  }
}

class _OmittedBanner extends ConsumerStatefulWidget {
  const _OmittedBanner({required this.ticketId});
  final String ticketId;

  @override
  ConsumerState<_OmittedBanner> createState() => _OmittedBannerState();
}

class _OmittedBannerState extends ConsumerState<_OmittedBanner> {
  bool _busy = false;
  String? _error;

  Future<void> _download() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(checklistBackfillProvider)(widget.ticketId);
    } catch (_) {
      if (mounted) setState(() => _error = 'Scaricamento non riuscito. Riprova tra poco.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = ref.watch(isOnlineProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.sm,
        AppSpacing.pagePadding,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InlineAlert(
            icon: LucideIcons.alertTriangle,
            color: context.colors.amber,
            message: online
                ? 'La checklist di questo ticket non è ancora scaricata sul telefono.'
                : 'La checklist di questo ticket non è ancora scaricata. Collegati a internet per averla.',
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(_error!, style: TextStyle(color: context.colors.red, fontSize: 12)),
          ],
          const SizedBox(height: AppSpacing.sm),
          AppButton.secondary(
            label: 'Scarica checklist',
            isLoading: _busy,
            onPressed: online && !_busy ? _download : null,
          ),
        ],
      ),
    );
  }
}

class _ItemView extends StatelessWidget {
  const _ItemView({
    required this.item,
    required this.reportId,
    required this.live,
    required this.onToggle,
    required this.showAssetName,
  });

  final ChecklistListItem item;
  final String? reportId;
  final Map<String, ChecklistAnswer> live;
  final ValueChanged<String> onToggle;
  final bool showAssetName;

  @override
  Widget build(BuildContext context) {
    return switch (item) {
      LibrettoHeaderItem i => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.pagePadding,
          AppSpacing.lg,
          AppSpacing.pagePadding,
          AppSpacing.xs,
        ),
        child: Row(
          children: [
            Icon(LucideIcons.package, size: 16, color: context.colors.inkMuted),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                i.libretto.name,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: context.colors.ink),
              ),
            ),
            Text('${i.childCount} asset', style: TextStyle(fontSize: 12, color: context.colors.inkMuted)),
          ],
        ),
      ),
      AssetHeaderItem i => _AssetHeader(item: i, onToggle: onToggle),
      ControlGroupItem i => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.pagePadding + 8, AppSpacing.sm, AppSpacing.pagePadding, 2),
        child: Text(i.path, style: TextStyle(fontSize: 11, color: context.colors.inkMuted)),
      ),
      ControlItem i =>
        reportId != null && !i.control.isRetained
            ? EditableControlTile(reportId: reportId!, item: i, showAssetName: showAssetName)
            : ControlItemTile(item: i, answer: live[i.control.id], showAssetName: showAssetName),
      ControlHeaderItem i => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.pagePadding,
          AppSpacing.lg,
          AppSpacing.pagePadding,
          AppSpacing.xs,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                i.label,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: context.colors.ink),
              ),
            ),
            Text('${i.assetCount} asset', style: TextStyle(fontSize: 12, color: context.colors.inkMuted)),
          ],
        ),
      ),
    };
  }
}

class _AssetHeader extends StatelessWidget {
  const _AssetHeader({required this.item, required this.onToggle});

  final AssetHeaderItem item;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final a = item.asset;
    final p = item.progress;
    final c = context.colors;
    return InkWell(
      onTap: a.templated ? () => onToggle(a.assetId) : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding, vertical: AppSpacing.sm),
          child: Row(
            children: [
              Icon(
                a.templated
                    ? (item.expanded ? LucideIcons.chevronDown : LucideIcons.chevronRight)
                    : LucideIcons.minus,
                size: 18,
                color: c.inkMuted,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.name,
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: c.ink),
                    ),
                    if ((a.matricola ?? '').isNotEmpty)
                      Text('Matr. ${a.matricola}', style: TextStyle(fontSize: 12, color: c.inkMuted)),
                    if (!a.coveredNow)
                      Text('Non più nel ticket', style: TextStyle(fontSize: 12, color: c.amber))
                    else if (!a.templated)
                      Text(
                        a.legacyControllato ? 'Senza checklist · controllato' : 'Senza checklist',
                        style: TextStyle(fontSize: 12, color: c.inkMuted),
                      ),
                  ],
                ),
              ),
              if (a.templated) ...[
                if (p.requiredMissing > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: AppBadge(label: '${p.requiredMissing} obbl.', small: true, fgColor: c.amber),
                  ),
                if (p.exceptions > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: AppBadge(label: '${p.exceptions} ecc.', small: true, fgColor: c.red),
                  ),
                Text('${p.answered}/${p.total}', style: TextStyle(fontSize: 13, color: c.inkMuted)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One checklist row, read-only: label, required mark, answer, note, exception marker. Task 6 adds
/// an editable sibling for the rapportino; this one is also what the ticket detail shows.
class ControlItemTile extends StatelessWidget {
  const ControlItemTile({super.key, required this.item, this.answer, this.showAssetName = false});

  final ControlItem item;
  final ChecklistAnswer? answer;
  final bool showAssetName;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final control = item.control;
    final effective = effectiveAnswer(control, answer);
    final value = describeAnswer(control, effective);
    final done = isAnswered(control, answer);
    final exception = isException(control, answer);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.pagePadding + 8, 6, AppSpacing.pagePadding, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            done ? LucideIcons.checkCircle : LucideIcons.circle,
            size: 18,
            color: done ? c.green : c.inkDisabled,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showAssetName)
                  Text(item.asset.name, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: c.ink)),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        control.label,
                        style: TextStyle(
                          fontSize: showAssetName ? 12 : 13,
                          fontWeight: showAssetName ? FontWeight.w400 : FontWeight.w600,
                          color: showAssetName ? c.inkMuted : c.ink,
                        ),
                      ),
                    ),
                    if (control.isRequired)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text('*', style: TextStyle(color: c.red, fontWeight: FontWeight.bold)),
                      ),
                    if (control.isRetained)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text('Non più richiesto', style: TextStyle(fontSize: 11, color: c.amber)),
                      ),
                  ],
                ),
                if (value != null)
                  Text(
                    value,
                    style: TextStyle(fontSize: 12, color: exception ? c.red : c.inkMuted),
                  ),
                if (effective.hasNote)
                  Text(effective.note!.trim(), style: TextStyle(fontSize: 12, color: c.inkMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
