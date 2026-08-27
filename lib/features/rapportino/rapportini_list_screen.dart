// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_vetro_palette.dart';
import '../../core/widgets/widgets.dart';
import '../../data/api/dio_client.dart';
import '../../data/local/app_database.dart';
import '../../presentation/providers/report_editor_providers.dart';
import 'create_draft.dart';
import 'rapportino_list_providers.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Filter enum
// ══════════════════════════════════════════════════════════════════════════════

/// Filter chips for the rapportini list.
///
/// All of them (bar Tutti/Bozza) reflect the real server lifecycle now — SyncService's
/// `submittedReports` upsert (sync_service.dart) keeps `stato` current, including
/// Respinto/Fatturato/Annullato, which used to never reach the device at all.
enum _RapportinoFilter { tutti, bozza, inviata, respinta, pagata, annullato }

extension _FilterLabel on _RapportinoFilter {
  String get label => switch (this) {
    _RapportinoFilter.tutti => 'Tutti',
    _RapportinoFilter.bozza => 'Bozza',
    _RapportinoFilter.inviata => 'Inviata',
    _RapportinoFilter.respinta => 'Respinta',
    _RapportinoFilter.pagata => 'Pagata',
    _RapportinoFilter.annullato => 'Annullato',
  };
}

// ══════════════════════════════════════════════════════════════════════════════
// Screen
// ══════════════════════════════════════════════════════════════════════════════

class RapportiniListScreen extends StatefulWidget {
  const RapportiniListScreen({super.key});

  @override
  State<RapportiniListScreen> createState() => _RapportiniListScreenState();
}

class _RapportiniListScreenState extends State<RapportiniListScreen> {
  _RapportinoFilter _filter = _RapportinoFilter.tutti;
  String _query = '';
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
        child: _RapportiniListBody(
          filter: _filter,
          query: _query,
          searchCtrl: _searchCtrl,
          onFilterChanged: (f) => setState(() => _filter = f),
          onQueryChanged: (q) => setState(() => _query = q),
        ),
      ),
      // Lifted over the floating nav like every other FAB in the app. This one was missed in the
      // clearance sweep because it is a custom widget rather than a bare AppFab, and HomeShell
      // sets extendBody: true — so the app's primary create-rapportino action sat under the pill.
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: context.navClearance - AppRack.navGap),
        child: _NewRapportinoFab(),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// FAB — creates a draft and navigates to the editor
// ══════════════════════════════════════════════════════════════════════════════

class _NewRapportinoFab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppFab(tooltip: 'Nuovo rapportino', onPressed: () => _createNewDraft(context, ref));
  }

  Future<void> _createNewDraft(BuildContext context, WidgetRef ref) async {
    final id = await createLocalDraft(ref, title: 'Nuovo rapportino');
    if (!context.mounted) return;
    if (id == null) {
      // Refused rather than authored by a placeholder. See createLocalDraft.
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Accedi per creare un rapportino.')));
      return;
    }
    context.push(AppRoutes.rapportiniEditor(id));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Body
// ══════════════════════════════════════════════════════════════════════════════

class _RapportiniListBody extends ConsumerWidget {
  const _RapportiniListBody({
    required this.filter,
    required this.query,
    required this.searchCtrl,
    required this.onFilterChanged,
    required this.onQueryChanged,
  });

  final _RapportinoFilter filter;
  final String query;
  final TextEditingController searchCtrl;
  final ValueChanged<_RapportinoFilter> onFilterChanged;
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draftsAsync = ref.watch(rapportiniListProvider);
    final allDrafts = draftsAsync.valueOrNull ?? [];

    // Filter by status chip.
    final filtered = allDrafts.where((d) {
      final label = rapportinoStatusLabel(d).toLowerCase();
      final matchFilter = switch (filter) {
        _RapportinoFilter.tutti => true,
        _RapportinoFilter.bozza => label == 'bozza',
        _RapportinoFilter.inviata => label == 'inviata',
        _RapportinoFilter.respinta => label == 'respinta',
        _RapportinoFilter.pagata => label == 'pagata',
        _RapportinoFilter.annullato => label == 'annullato',
      };
      final matchQuery = query.isEmpty || d.title.toLowerCase().contains(query.toLowerCase());
      return matchFilter && matchQuery;
    }).toList();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          // The filter chips below already do the filtering — this used to carry a second,
          // dead filter icon (`onTap: () {}`) doing nothing beside them. Same fix as the ticket
          // list: a control that looks tappable and isn't teaches distrust of the one that works.
          child: ScreenHeader(title: 'Rapportini', subtitle: '${allDrafts.length} totali'),
        ),
        SliverToBoxAdapter(
          child: AppSearchBar(
            controller: searchCtrl,
            hint: 'Cerca rapportino…',
            onChanged: onQueryChanged,
          ),
        ),
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
                children: _RapportinoFilter.values.map((f) {
                  return Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: AppChip(
                      label: f.label,
                      active: filter == f,
                      onTap: () => onFilterChanged(f),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        if (draftsAsync.isLoading)
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
            child: EmptyState(
              icon: LucideIcons.fileText,
              title: 'Nessun rapportino',
              body: 'I rapportini appariranno qui.',
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate((context, i) {
              return _RapportinoRow(draft: filtered[i], isLast: i == filtered.length - 1);
            }, childCount: filtered.length),
          ),
        SliverPadding(padding: EdgeInsets.only(bottom: context.navClearance)),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Row
// ══════════════════════════════════════════════════════════════════════════════

/// Vetro (module #3). Was a [ListRow] — Cassetta's shared rack-cell primitive, used at 28 call
/// sites app-wide, not touched here or anywhere else in this pass (see every other Vetro module's
/// own note on this). Rebuilt in the same flat-row-with-stripe shape the ticket list already
/// established: no [VetroGlass] blur, this list can run long and a per-row backdrop filter during
/// scroll is a real cost, not a style choice (see `_TicketRow`'s own doc comment).
///
/// The stripe replaces `strapped` — Cassetta's brand-accent ledge for "still needs finishing" —
/// with the same Vetro tint used everywhere else for "this one needs you," so a technician reads
/// one accent language across the whole app, not the safety-orange strap on this list and the
/// indigo tint on Tickets.
class _RapportinoRow extends ConsumerWidget {
  const _RapportinoRow({required this.draft, required this.isLast});

  final DraftReport draft;
  final bool isLast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = context.vetro;
    final summary = ref.watch(rapportinoRowSummaryProvider(draft.id));

    final staffCount = summary.staffCount;
    final materialiCount = summary.materialiCount;
    final oreLabel = summary.oreLabel;

    final statusLabel = rapportinoStatusLabel(draft);
    final isSubmitted = rapportinoIsSubmitted(draft);
    final hasBothSigs =
        draft.customerSignatureAllegatoId != null && draft.technicianSignatureAllegatoId != null;

    final dateLabel = DateFormat(
      'dd/MM/yy',
      'it',
    ).format((draft.updatedAt ?? draft.createdAt).toLocal());

    // Subtitle: tecnico count · ore · materiali count.
    //
    // Used to lead with `#$shortId` — eight hex characters of the draft's own row id, the same
    // "identifier a human cannot recognise" bug already fixed on the ticket list. A rapportino
    // has no `numero` synced locally (unlike a ticket), so there is nothing real to show in its
    // place; the title and this summary carry the row on their own, same as a numberless ticket.
    final subParts = <String>[
      if (staffCount > 0) '$staffCount tecnico',
      oreLabel,
      '$materialiCount mat.',
    ];
    final subtitle = subParts.join(' · ');

    final row = InkWell(
      onTap: () {
        if (isSubmitted) {
          context.push(AppRoutes.rapportiniView(draft.id));
        } else {
          context.push(AppRoutes.rapportiniEditor(draft.id));
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding, vertical: 11),
        decoration: BoxDecoration(
          border: isLast ? null : Border(bottom: BorderSide(color: v.hairline)),
        ),
        // IntrinsicHeight for the stripe — same reasoning as `_TicketRow`'s own comment: this row
        // sits in a SliverChildBuilderDelegate item with no bounded height for a bare
        // `crossAxisAlignment: stretch` to stretch into.
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 3,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: isSubmitted ? context.colors.inkDisabled : v.tint,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Stack(
                children: [
                  const RowIconTile(icon: LucideIcons.fileText),
                  if (hasBothSigs)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: context.colors.green,
                          shape: BoxShape.circle,
                          border: Border.all(color: context.colors.surface, width: 1.5),
                        ),
                        child: Icon(LucideIcons.penTool, size: 8, color: AppColors.WHITE),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      draft.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: context.colors.ink,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: context.colors.inkMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  StatusPill(stato: statusLabel, small: true, outlined: true),
                  const SizedBox(height: 2),
                  Text(dateLabel, style: TextStyle(fontSize: 10, color: context.colors.inkMuted)),
                ],
              ),
              // A swipe is the only way a mouse/keyboard/TalkBack/VoiceOver user cannot perform —
              // this button reaches the exact same delete path (_confirmDeleteDraft) so both ways
              // to delete a draft agree on what "delete" does, not just on how you trigger it.
              if (statusLabel == 'Bozza')
                IconButton(
                  icon: Icon(LucideIcons.trash2, size: 18, color: context.colors.inkMuted),
                  tooltip: 'Elimina bozza',
                  onPressed: () => _confirmDeleteDraft(context, ref, draft),
                ),
              const SizedBox(width: 6),
              Icon(LucideIcons.chevronRight, size: 16, color: context.colors.inkDisabled),
            ],
          ),
        ),
      ),
    );

    // Only a still-editable draft can be deleted — a submitted report goes through the office
    // Annulla workflow instead (ReportsController.Delete rejects anything past Bozza too).
    if (statusLabel != 'Bozza') return row;

    return Dismissible(
      key: ValueKey('rapportino-${draft.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(LucideIcons.trash2, color: context.colors.red),
      ),
      confirmDismiss: (_) => _confirmDeleteDraft(context, ref, draft),
      child: row,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Delete (Bozza only)
// ══════════════════════════════════════════════════════════════════════════════

Future<bool> _confirmDeleteDraft(BuildContext context, WidgetRef ref, DraftReport draft) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Eliminare il rapportino?'),
      content: Text('"${draft.title}" verrà eliminato definitivamente.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: context.colors.red),
          child: const Text('Elimina'),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;

  await ref.read(draftReportRepositoryProvider).deleteDraft(draft.id);

  // Best-effort, not awaited by the dismiss animation: the draft may or may not exist
  // server-side yet (an attachment upload can create the row before Invia does) — either way
  // local state is authoritative for a Bozza the technician is still working on, so a failure
  // here (offline, already gone, 404) is not worth surfacing.
  unawaited(_bestEffortServerDelete(ref, draft.id));

  return true;
}

Future<void> _bestEffortServerDelete(WidgetRef ref, String reportId) async {
  try {
    await ref.read(dioProvider).delete<void>('/api/reports/$reportId');
  } catch (_) {
    // See _confirmDeleteDraft's doc comment.
  }
}
