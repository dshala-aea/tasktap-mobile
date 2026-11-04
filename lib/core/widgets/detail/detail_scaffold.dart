import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';
import '../../theme/app_rack.dart';
import '../../theme/app_spacing.dart';
import '../app_button.dart';
import '../app_card.dart';
import '../screen_header.dart';
import '../status_stamp.dart';
import '../unavailable_state.dart';
import 'detail_hero.dart';
import 'detail_section.dart';

/// Height of the sticky bar shown once the hero has scrolled away.
const double _collapsedBarHeight = 56;

/// The app's minimum touch target, shared with [DetailHero].
const double _minTouchTarget = 48;

/// The height of the placeholder hero used by [DetailScaffold.loading].
const double _loadingHeroHeight = 168;

/// Which body [DetailScaffold] renders inside its shared header frame.
enum _DetailScaffoldMode { content, loading, unavailable }

/// The shared frame for every detail screen.
///
/// Owns the generic header, the scroll frame, pull-to-refresh, page padding and max width. Screens
/// supply a [DetailHeroData] and an ordered list of [DetailSectionData]; the frame stays agnostic
/// about what each section means and never reads from a provider or the network.
class DetailScaffold extends StatefulWidget {
  const DetailScaffold({
    super.key,
    required this.screenTitle,
    required DetailHeroData this.hero,
    this.headerActions = const [],
    this.expandedExtra,
    required this.sections,
    this.onRefresh,
    this.maxWidth = 720,
    this.fab,
  }) : _mode = _DetailScaffoldMode.content,
       _unavailableIcon = null,
       _unavailableTitle = null,
       _unavailableReason = null,
       _onRetry = null;

  /// A header and a hero-shaped skeleton, with no full-screen spinner and no layout jump.
  const DetailScaffold.loading({
    super.key,
    required this.screenTitle,
    this.headerActions = const [],
  }) : hero = null,
       expandedExtra = null,
       sections = const [],
       onRefresh = null,
       maxWidth = 720,
       fab = null,
       _mode = _DetailScaffoldMode.loading,
       _unavailableIcon = null,
       _unavailableTitle = null,
       _unavailableReason = null,
       _onRetry = null;

  /// A header and the standard [UnavailableState] with an optional retry action.
  const DetailScaffold.unavailable({
    super.key,
    required this.screenTitle,
    required IconData icon,
    required String title,
    required String reason,
    VoidCallback? onRetry,
    this.headerActions = const [],
  }) : hero = null,
       expandedExtra = null,
       sections = const [],
       onRefresh = null,
       maxWidth = 720,
       fab = null,
       _mode = _DetailScaffoldMode.unavailable,
       _unavailableIcon = icon,
       _unavailableTitle = title,
       _unavailableReason = reason,
       _onRetry = onRetry;

  final String screenTitle;
  final DetailHeroData? hero;
  final List<Widget> headerActions;
  final Widget? expandedExtra;
  final List<DetailSectionData> sections;
  final Future<void> Function()? onRefresh;
  final double maxWidth;
  final Widget? fab;

  final _DetailScaffoldMode _mode;
  final IconData? _unavailableIcon;
  final String? _unavailableTitle;
  final String? _unavailableReason;
  final VoidCallback? _onRetry;

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
    return switch (widget._mode) {
      _DetailScaffoldMode.content => _frame(context, child: _content(context)),
      _DetailScaffoldMode.loading => _frame(
        context,
        child: _loadingBody(context),
      ),
      _DetailScaffoldMode.unavailable => _frame(
        context,
        child: _unavailableBody(),
      ),
    };
  }

  Widget _frame(BuildContext context, {required Widget child}) {
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
            Expanded(child: child),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final hero = widget.hero!;
    final scrollView = CustomScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: _framed(
            key: const Key('detail-content'),
            child: DetailHero(key: _heroKey, data: hero),
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

    return NotificationListener<ScrollNotification>(
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
              child: ExcludeFocus(
                excluding: !_barVisible,
                child: ExcludeSemantics(
                  excluding: !_barVisible,
                  child: AnimatedSlide(
                    offset: _barVisible ? Offset.zero : const Offset(0, -1),
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
          ),
        ],
      ),
    );
  }

  Widget _loadingBody(BuildContext context) {
    final rule = context.colors.borderLight;

    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: widget.maxWidth),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.pagePadding,
              vertical: AppSpacing.xl,
            ),
            child: AppCard(
              key: const Key('detail-loading-skeleton'),
              padding: const EdgeInsets.all(AppSpacing.base),
              child: SizedBox(
                height: _loadingHeroHeight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _SkeletonBar(widthFactor: 0.28, height: 22, color: rule),
                    _SkeletonBar(widthFactor: 0.85, height: 28, color: rule),
                    _SkeletonBar(widthFactor: 0.55, height: 14, color: rule),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _unavailableBody() {
    final onRetry = widget._onRetry;

    return UnavailableState(
      icon: widget._unavailableIcon!,
      titolo: widget._unavailableTitle!,
      motivo: widget._unavailableReason!,
      action: onRetry == null
          ? null
          : ConstrainedBox(
              constraints: const BoxConstraints(minHeight: _minTouchTarget),
              child: AppButton(label: 'Riprova', onPressed: onRetry),
            ),
    );
  }

  /// The sticky summary: the same status and primary action as [DetailScaffold.hero], at 56px.
  ///
  /// The key is only attached while the bar is visible, so tests (and anything else walking the
  /// tree) never mistake the off-screen copy for the real thing.
  Widget _collapsedBar(BuildContext context) {
    final colors = context.colors;
    final action = widget.hero!.primaryAction;

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
                  stato: widget.hero!.status.label,
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

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({
    required this.widthFactor,
    required this.height,
    required this.color,
  });

  final double widthFactor;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: AppRack.insetShape,
        ),
      ),
    );
  }
}
