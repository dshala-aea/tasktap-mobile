import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../theme/app_palette.dart';
import '../../theme/app_rack.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../app_search_bar.dart';
import '../empty_state.dart';
import '../screen_header.dart';
import '../unavailable_state.dart';
import 'list_document_row.dart';
import 'list_filter_row.dart';
import 'list_group_header.dart';
import 'list_loading_skeleton.dart';
import 'list_models.dart';
import 'list_summary_footer.dart';

/// A header text action (`Nuovo`) in the prototype's mono uppercase stamp-red treatment.
///
/// Kept a real 44px target without changing the 8.5px glyphs. Pass `null` when the role cannot
/// write: permission-denied hides the action by simply not supplying it.
class ListHeaderAction extends StatelessWidget {
  const ListHeaderAction({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          foregroundColor: context.colors.accentInk,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          label.toUpperCase(),
          style: AppTextStyles.docCode.copyWith(
            fontSize: 8.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.42,
            color: context.colors.accentInk,
          ),
        ),
      ),
    );
  }
}

/// The shared list shell from `prototypes/list-screens.html`: header (title, subtitle, optional
/// `Nuovo` and extra header actions) → search → quick-filter chips + red `Filtri` → group headings
/// with counts → document rows → summary footer.
///
/// Data-driven and presentation-only: it never reads a provider, a route or a repository. Wave-1
/// screens keep their existing providers/filters and hand the shell the resulting groups.
///
/// ```dart
/// ListShell(
///   title: 'Cantieri',
///   subtitle: 'Cosa devo seguire oggi…',
///   action: ListHeaderAction(label: 'Nuovo', onPressed: ...),
///   banner: const OfflineSyncBanner(),
///   searchController: _searchCtrl,
///   onSearchChanged: (q) => setState(...),
///   filters: const [
///     ListFilterChipData(label: 'Attivi'),
///     ListFilterChipData(label: 'Tutti'),
///   ],
///   activeFilterIndex: 0,
///   onFilterSelected: (chip) => setState(...),
///   onOpenFilters: () => showFilterSheet(...),
///   groups: [...],
///   summary: const ListSummaryData(left: '8 cantieri attivi', right: '2 oggi'),
/// )
/// ```
class ListShell extends StatelessWidget {
  const ListShell({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    this.headerActions = const [],
    this.banner,
    this.searchHint = 'Cerca…',
    this.searchController,
    this.onSearchChanged,
    this.filters = const [],
    this.activeFilterId,
    this.activeFilterIndex,
    this.onFilterSelected,
    this.onOpenFilters,
    this.groups = const [],
    this.summary,
    this.state = ListShellState.content,
    this.empty,
    this.unavailable,
    this.onRefresh,
    this.bottomPadding,
    this.maxWidth = 720,
  });

  final String title;
  final String? subtitle;

  /// The primary header action (`Nuovo`). Omit for read-only roles.
  final Widget? action;

  /// Extra header actions (Materiali hosts three icon actions here).
  final List<Widget> headerActions;

  /// Usually `const OfflineSyncBanner()`; the shell only places it above the header.
  final Widget? banner;

  final String searchHint;
  final TextEditingController? searchController;
  final ValueChanged<String>? onSearchChanged;

  final List<ListFilterChipData> filters;
  final String? activeFilterId;
  final int? activeFilterIndex;
  final ValueChanged<ListFilterChipData>? onFilterSelected;
  final VoidCallback? onOpenFilters;

  final List<ListGroupData> groups;
  final ListSummaryData? summary;

  final ListShellState state;

  /// Shown when [state] is content and there are no groups. Pass an [EmptyState] for an empty
  /// filter result or an [UnavailableState] for an empty catalogue.
  final Widget? empty;

  /// Shown when [state] is [ListShellState.unavailable]. Must carry the retry action.
  final Widget? unavailable;

  final Future<void> Function()? onRefresh;

  /// Defaults to the floating-nav clearance.
  final double? bottomPadding;

  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final header = ScreenHeader(
      title: title,
      subtitle: subtitle,
      subtitleMaxLines: 2,
      actions: [...headerActions, ?action],
    );

    final body = switch (state) {
      ListShellState.loading => _scrollable(
        context,
        const ListLoadingSkeleton(),
      ),
      ListShellState.unavailable => _scrollable(
        context,
        unavailable ??
            const UnavailableState(
              icon: LucideIcons.alertTriangle,
              titolo: 'Lista non disponibile',
              motivo: 'Non è stato possibile leggere i dati. Riprova.',
            ),
      ),
      ListShellState.content => _content(context),
    };

    return Scaffold(
      backgroundColor: colors.bg2,
      body: SafeArea(
        child: Column(
          children: [
            ?banner,
            header,
            AppSearchBar(
              controller: searchController,
              hint: searchHint,
              onChanged: onSearchChanged,
            ),
            if (filters.isNotEmpty || onOpenFilters != null)
              ListFilterRow(
                filters: filters,
                activeId: activeFilterId,
                activeIndex: activeFilterIndex,
                onSelected: onFilterSelected,
                onOpenFilters: onOpenFilters,
              ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  Widget _scrollable(BuildContext context, Widget child) {
    return RefreshIndicator(
      onRefresh: onRefresh ?? () async {},
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: child,
            ),
          ),
          SizedBox(height: bottomPadding ?? context.navClearance),
        ],
      ),
    );
  }

  Widget _content(BuildContext context) {
    final bottom = bottomPadding ?? context.navClearance;
    final visibleGroups = groups.where((g) => g.rows.isNotEmpty).toList();

    final scrollView = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (visibleGroups.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child:
                empty ??
                const EmptyState(
                  icon: LucideIcons.searchX,
                  title: 'Nessun risultato',
                  body: 'Nessun elemento corrisponde ai filtri selezionati.',
                ),
          )
        else ...[
          for (final group in visibleGroups) ...[
            SliverToBoxAdapter(
              child: _framed(
                child: ListGroupHeader(title: group.title, count: group.count),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.pagePadding,
              ),
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
          if (summary != null)
            SliverToBoxAdapter(
              child: _framed(child: ListSummaryFooter(data: summary!)),
            ),
          SliverToBoxAdapter(child: SizedBox(height: bottom)),
        ],
      ],
    );

    if (onRefresh == null) return scrollView;
    return RefreshIndicator(onRefresh: onRefresh!, child: scrollView);
  }

  Widget _framed({required Widget child}) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.pagePadding,
          ),
          child: child,
        ),
      ),
    );
  }
}
