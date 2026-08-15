// dart format width=100
import 'package:flutter/material.dart';
import '../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/widgets.dart';
import '../../data/local/app_database.dart';
import 'create_draft.dart';
import 'rapportino_list_providers.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Filter enum
// ══════════════════════════════════════════════════════════════════════════════

/// Filter chips for the rapportini list.
///
/// Pagata / Annullato show empty until the backend syncs the full report
/// lifecycle back to the device.
// TODO(backend): sync submitted-report lifecycle for Pagata/Annullato states.
enum _RapportinoFilter { tutti, bozza, inviata, pagata, annullato }

extension _FilterLabel on _RapportinoFilter {
  String get label => switch (this) {
    _RapportinoFilter.tutti => 'Tutti',
    _RapportinoFilter.bozza => 'Bozza',
    _RapportinoFilter.inviata => 'Inviata',
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
        // Pagata/Annullato: no local data yet — always empty until backend sync.
        _RapportinoFilter.pagata => false,
        _RapportinoFilter.annullato => false,
      };
      final matchQuery = query.isEmpty || d.title.toLowerCase().contains(query.toLowerCase());
      return matchFilter && matchQuery;
    }).toList();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: ScreenHeader(
            title: 'Rapportini',
            subtitle: '${allDrafts.length} totali',
            actions: [
              HeaderIconBtn(icon: LucideIcons.filter, label: 'Filtra rapportini', onTap: () {}),
            ],
          ),
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
            padding: const EdgeInsets.fromLTRB(19, 0, 19, 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _RapportinoFilter.values.map((f) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
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
              child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator()),
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

class _RapportinoRow extends ConsumerWidget {
  const _RapportinoRow({required this.draft, required this.isLast});

  final DraftReport draft;
  final bool isLast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffAsync = ref.watch(rapportinoStaffProvider(draft.id));
    final materialiAsync = ref.watch(rapportinoMaterialiProvider(draft.id));
    final oreLabel = ref.watch(rapportinoOreProvider(draft.id));

    final staffCount = staffAsync.valueOrNull?.length ?? 0;
    final materialiCount = materialiAsync.valueOrNull?.length ?? 0;

    final statusLabel = rapportinoStatusLabel(draft);
    final isSubmitted = rapportinoIsSubmitted(draft);
    final hasBothSigs =
        draft.customerSignatureAllegatoId != null && draft.technicianSignatureAllegatoId != null;

    final dateLabel = DateFormat(
      'dd/MM/yy',
      'it',
    ).format((draft.updatedAt ?? draft.createdAt).toLocal());

    // Short id for display
    final shortId = draft.id.length > 8 ? draft.id.substring(0, 8) : draft.id;

    // Subtitle: tecnico count · ore · materiali count
    final subParts = <String>[
      if (staffCount > 0) '$staffCount tecnico',
      oreLabel,
      '$materialiCount mat.',
    ];
    final subtitle = subParts.join(' · ');

    return ListRow(
      leading: Stack(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: context.colors.bg3,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(LucideIcons.fileText, size: 20, color: context.colors.inkMuted),
          ),
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
      title: draft.title,
      subtitle: '#$shortId · $subtitle',
      meta: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusPill(stato: statusLabel, small: true),
          const SizedBox(height: 2),
          Text(dateLabel, style: TextStyle(fontSize: 10, color: context.colors.inkMuted)),
        ],
      ),
      showDivider: !isLast,
      onTap: () {
        if (isSubmitted) {
          context.push(AppRoutes.rapportiniView(draft.id));
        } else {
          context.push(AppRoutes.rapportiniEditor(draft.id));
        }
      },
    );
  }
}
