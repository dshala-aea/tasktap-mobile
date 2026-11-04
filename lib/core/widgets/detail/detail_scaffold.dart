import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';
import '../../theme/app_rack.dart';
import '../../theme/app_spacing.dart';
import '../screen_header.dart';
import 'detail_hero.dart';
import 'detail_section.dart';

/// The shared frame for every detail screen.
///
/// Owns the generic header, the scroll frame, pull-to-refresh, page padding and max width. Screens
/// supply a [DetailHeroData] and an ordered list of [DetailSectionData]; the frame stays agnostic
/// about what each section means and never reads from a provider or the network.
class DetailScaffold extends StatefulWidget {
  const DetailScaffold({
    super.key,
    required this.screenTitle,
    required this.hero,
    this.headerActions = const [],
    this.expandedExtra,
    required this.sections,
    this.onRefresh,
    this.maxWidth = 720,
    this.fab,
  });

  final String screenTitle;
  final DetailHeroData hero;
  final List<Widget> headerActions;
  final Widget? expandedExtra;
  final List<DetailSectionData> sections;
  final Future<void> Function()? onRefresh;
  final double maxWidth;
  final Widget? fab;

  @override
  State<DetailScaffold> createState() => _DetailScaffoldState();
}

class _DetailScaffoldState extends State<DetailScaffold> {
  /// Owned here because the collapsing bar (added later) needs to react to this same scroll.
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scrollView = CustomScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: _framed(
            key: const Key('detail-content'),
            child: DetailHero(data: widget.hero),
          ),
        ),
        if (widget.expandedExtra != null)
          SliverToBoxAdapter(child: _framed(child: widget.expandedExtra!)),
        for (final section in widget.sections.where((s) => !s.isEmpty))
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xl),
              child: _framed(child: DetailSection(data: section)),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
      ],
    );

    return Scaffold(
      backgroundColor: context.colors.bg2,
      floatingActionButton: widget.fab == null
          ? null
          : Padding(
              padding: EdgeInsets.only(bottom: context.fabSafeBottom),
              child: widget.fab,
            ),
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: widget.screenTitle,
              showBack: true,
              actions: widget.headerActions,
            ),
            Expanded(
              child: widget.onRefresh == null
                  ? scrollView
                  : RefreshIndicator(
                      onRefresh: widget.onRefresh!,
                      child: scrollView,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Centers a sliver's content at [DetailScaffold.maxWidth] with the standard page gutter.
  Widget _framed({Key? key, required Widget child}) {
    return Center(
      child: ConstrainedBox(
        key: key,
        constraints: BoxConstraints(maxWidth: widget.maxWidth),
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
