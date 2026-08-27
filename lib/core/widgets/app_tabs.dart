import 'package:flutter/material.dart';

import 'app_tappable.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_vetro_palette.dart';

/// A single tab descriptor with an optional count pill.
class AppTab {
  const AppTab({required this.label, this.count});

  final String label;
  final int? count;
}

/// Horizontal scrolling tabs — Inter 700/12, active DARK + 2 px tint underline
/// (inactive MUTED), 12/14 padding, optional count pill.
///
/// ```dart
/// AppTabs(
///   tabs: const [AppTab(label: 'Tutti', count: 12), AppTab(label: 'Aperti')],
///   selectedIndex: 0,
///   onSelected: (i) {},
/// );
/// ```
class AppTabs extends StatefulWidget {
  const AppTabs({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<AppTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// The strip's fixed height.
  ///
  /// Exposed because [SliverPinnedTabs] has to declare the same number as a sliver extent, and a
  /// pinned header whose extent disagrees with its child either clips the underline or leaves a
  /// gap under it.
  static const double height = 44;

  @override
  State<AppTabs> createState() => _AppTabsState();
}

/// [AppTabs] as a sliver that stays put once it reaches the top.
///
/// The ticket detail screen put its strip in a `SliverToBoxAdapter`, so it scrolled away with
/// everything else. Reading anything in a tab meant scrolling past the timer, the fact card and
/// the strip itself — and then switching tab meant scrolling back up to find the control, choosing
/// one, and scrolling down again. With seven tabs that is the whole interaction, and it is why the
/// screen read as "too many tabs" when the count was not really the problem.
///
/// Pinned, the strip is reachable from anywhere in the content, and which tab you are in stays on
/// screen while you read it.
///
/// Paints an opaque background on purpose: a pinned header is drawn over the content scrolling
/// beneath it, and a transparent one shows the rows sliding through the labels.
class SliverPinnedTabs extends StatelessWidget {
  const SliverPinnedTabs({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<AppTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _PinnedTabsDelegate(
        tabs: tabs,
        selectedIndex: selectedIndex,
        onSelected: onSelected,
        background: context.colors.bg2,
        divider: context.colors.borderLight,
      ),
    );
  }
}

class _PinnedTabsDelegate extends SliverPersistentHeaderDelegate {
  const _PinnedTabsDelegate({
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
    required this.background,
    required this.divider,
  });

  final List<AppTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Color background;
  final Color divider;

  @override
  double get minExtent => AppTabs.height;

  @override
  double get maxExtent => AppTabs.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        // Only once something is actually passing underneath. A permanent rule would draw a second
        // line under the strip while it is still sitting in the page, competing with the active
        // tab's own accent underline.
        border: overlapsContent
            ? Border(bottom: BorderSide(color: divider, width: 1))
            : null,
      ),
      child: AppTabs(tabs: tabs, selectedIndex: selectedIndex, onSelected: onSelected),
    );
  }

  /// [onSelected] is deliberately not compared.
  ///
  /// Call sites build it as a closure over `setState`, so it is a new object on every parent build
  /// and identity-comparing it would rebuild the strip on every frame the screen rebuilds — which
  /// would also restart the auto-scroll that reveals the selected tab. What it *does* is fixed, so
  /// the fields that change what the strip shows are the ones that matter here.
  @override
  bool shouldRebuild(_PinnedTabsDelegate old) =>
      old.selectedIndex != selectedIndex ||
      old.tabs != tabs ||
      old.background != background ||
      old.divider != divider;
}

class _AppTabsState extends State<AppTabs> {
  final _controller = ScrollController();
  final _keys = <int, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    // The ticket screen has seven tabs. Opening it on tab six — which happens on any return to a
    // screen that remembers where you were — used to show the strip scrolled to the start, with
    // the selected tab off to the right and nothing saying so.
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected(animate: false));
  }

  @override
  void didUpdateWidget(AppTabs old) {
    super.didUpdateWidget(old);
    if (old.selectedIndex != widget.selectedIndex) _revealSelected();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _revealSelected({bool animate = true, int attempt = 0}) {
    if (!_controller.hasClients || !mounted) return;

    final ctx = _keys[widget.selectedIndex]?.currentContext;
    if (ctx == null) {
      // The list is lazy, so a tab beyond the first viewport has not been built and has no
      // context to scroll to. Jump roughly to where it must be, which builds it, then finish the
      // job on the next frame. Bounded, so a strip that never resolves stops trying rather than
      // spinning a frame callback forever.
      if (attempt >= 3 || widget.tabs.length < 2) return;
      final position = _controller.position;
      _controller.jumpTo(
        position.maxScrollExtent * (widget.selectedIndex / (widget.tabs.length - 1)),
      );
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _revealSelected(animate: false, attempt: attempt + 1),
      );
      return;
    }

    Scrollable.ensureVisible(
      ctx,
      duration: animate ? const Duration(milliseconds: 240) : Duration.zero,
      curve: Curves.easeOut,
      // Not flush against the edge: a tab touching the frame reads as the last one.
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      alignment: 0.5,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = widget.tabs;
    final selectedIndex = widget.selectedIndex;
    final onSelected = widget.onSelected;

    return SizedBox(
      height: AppTabs.height,
      // Fades at both ends, so a strip that continues past the frame looks like one. Without it
      // seven tabs and four tabs are indistinguishable until you happen to drag.
      child: ShaderMask(
        shaderCallback: (rect) => LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: const [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
          stops: const [0, 0.03, 0.97, 1],
        ).createShader(rect),
        blendMode: BlendMode.dstIn,
        child: ListView.builder(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          itemCount: tabs.length,
          itemBuilder: (context, i) {
            final active = i == selectedIndex;
            final tab = tabs[i];
            return Semantics(
              key: _keys.putIfAbsent(i, GlobalKey.new),
              button: true,
              selected: active,
              label: tab.label,
              child: AppTappable(
                onTap: () => onSelected(i),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: Border(
                  bottom: BorderSide(
                    color: active ? context.vetro.tint : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tab.label,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: active ? context.colors.ink : context.colors.inkMuted,
                      ),
                    ),
                    if (tab.count != null) ...[
                      const SizedBox(width: 6),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: active
                              ? context.vetro.tint.withAlpha(31)
                              : context.colors.bg3,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          child: Text(
                            '${tab.count}',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: active ? context.vetro.tint : context.colors.inkMuted,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
