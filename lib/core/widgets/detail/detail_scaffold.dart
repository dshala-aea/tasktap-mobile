import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';
import '../../theme/app_rack.dart';
import '../../theme/app_spacing.dart';
import '../app_button.dart';
import '../screen_header.dart';
import '../status_stamp.dart';
import 'detail_hero.dart';
import 'detail_section.dart';

/// Height of the sticky bar shown once the hero has scrolled away.
const double _collapsedBarHeight = 56;

/// The app's minimum touch target, shared with [DetailHero].
const double _minTouchTarget = 48;

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
  /// Owned here because the collapsing bar reacts to this same scroll.
  final ScrollController _scrollController = ScrollController();

  /// The hero's own render box, measured to decide when its bottom passes the viewport top.
  final GlobalKey _heroKey = GlobalKey();

  /// The scroll area, whose top edge is the collapse threshold.
  final GlobalKey _viewportKey = GlobalKey();

  bool _barVisible = false;
  bool _barSyncScheduled = false;

  @override
  void initState() {
    super.initState();
    // A restored scroll offset may already hide the hero before the first notification.
    _scheduleBarSync();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Scroll notifications arrive before the frame that lays out the new offset, so measure after
  /// that frame instead of trusting a stale render box.
  bool _handleScrollNotification(ScrollNotification notification) {
    _scheduleBarSync();
    return false;
  }

  void _scheduleBarSync() {
    if (_barSyncScheduled || !mounted) return;
    _barSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _barSyncScheduled = false;
      if (!mounted) return;
      _syncBarVisibility();
    });
  }

  void _syncBarVisibility() {
    final heroObject = _heroKey.currentContext?.findRenderObject();
    final viewportObject = _viewportKey.currentContext?.findRenderObject();
    if (heroObject is! RenderBox || viewportObject is! RenderBox) return;

    final heroBottom = heroObject
        .localToGlobal(Offset(0, heroObject.size.height))
        .dy;
    final viewportTop = viewportObject.localToGlobal(Offset.zero).dy;
    final shouldShow = heroBottom <= viewportTop;
    if (shouldShow == _barVisible) return;
    setState(() => _barVisible = shouldShow);
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
            child: DetailHero(key: _heroKey, data: widget.hero),
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

    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 150);

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
              child: NotificationListener<ScrollNotification>(
                onNotification: _handleScrollNotification,
                child: Stack(
                  key: _viewportKey,
                  children: [
                    Positioned.fill(
                      child: widget.onRefresh == null
                          ? scrollView
                          : RefreshIndicator(
                              onRefresh: widget.onRefresh!,
                              child: scrollView,
                            ),
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        ignoring: !_barVisible,
                        child: ExcludeSemantics(
                          excluding: !_barVisible,
                          child: AnimatedSlide(
                            offset: _barVisible
                                ? Offset.zero
                                : const Offset(0, -1),
                            duration: duration,
                            curve: Curves.easeOut,
                            child: AnimatedOpacity(
                              opacity: _barVisible ? 1 : 0,
                              duration: duration,
                              curve: Curves.easeOut,
                              child: _collapsedBar(context),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The sticky summary: the same status and primary action as [DetailScaffold.hero], at 56px.
  ///
  /// The key is only attached while the bar is visible, so tests (and anything else walking the
  /// tree) never mistake the off-screen copy for the real thing.
  Widget _collapsedBar(BuildContext context) {
    final colors = context.colors;
    final action = widget.hero.primaryAction;

    return Container(
      key: _barVisible ? const Key('detail-collapsed-bar') : null,
      height: _collapsedBarHeight,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.borderLight)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: widget.maxWidth),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.pagePadding,
            ),
            child: Row(
              children: [
                StatusStamp(
                  stato: widget.hero.status.label,
                  size: StampSize.small,
                ),
                if (action != null) ...[
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: _minTouchTarget,
                        ),
                        child: AppButton(
                          label: action.label,
                          icon: action.icon,
                          onPressed: action.enabled ? action.onPressed : null,
                          size: AppButtonSize.sm,
                          fullWidth: false,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
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
