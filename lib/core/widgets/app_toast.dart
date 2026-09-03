// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../theme/app_colors.dart';
import '../theme/app_rack.dart';
import '../theme/app_spacing.dart';
import 'app_tappable.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

// ══════════════════════════════════════════════════════════════════════════════
// showAppToast
//
// Replaces the app's ~33 ScaffoldMessenger.showSnackBar call sites with one shared, flat-Documento
// floating toast — same call shape (a message + a tone that maps to the existing status colors)
// so migrating a call site is mechanical, not a rewrite.
//
// An OverlayEntry, not ScaffoldMessenger: a SnackBar is queued and owned by the nearest Scaffold,
// which is exactly why every call site above needed its own `context.colors.X` background pick —
// there is no single shared place those lived. An overlay sits above the whole app, is not tied
// to any one Scaffold, and reads `context.colors` for its own styling regardless of which screen
// called it from.
// ══════════════════════════════════════════════════════════════════════════════

enum ToastTone { info, success, warning, error }

OverlayEntry? _currentToast;
Timer? _currentToastTimer;

/// Shows a floating toast. A second call replaces whatever is currently showing, same
/// one-at-a-time feel `ScaffoldMessenger`'s queue gave by default — a technician does not need to
/// read a backlog of stale toasts from actions they have already moved past.
void showAppToast(
  BuildContext context, {
  required String message,
  ToastTone tone = ToastTone.info,
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(milliseconds: 3500),
}) {
  _dismissCurrentToast();

  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  final key = GlobalKey<_ToastCardState>();

  entry = OverlayEntry(
    builder: (context) => _ToastCard(
      key: key,
      message: message,
      tone: tone,
      actionLabel: actionLabel,
      onAction: onAction == null
          ? null
          : () {
              onAction();
              _dismissCurrentToast();
            },
      onDismissed: _dismissCurrentToast,
      // Cancels the auto-dismiss Timer as soon as the card's State is disposed, however that
      // happened — a swipe/action/auto-dismiss all go through onDismissed above already, but a
      // widget tree torn down directly (a route pop, a test's pumpWidget(SizedBox.shrink()))
      // disposes the State without ever calling onDismissed, and a bare module-level Timer has
      // no lifecycle tie to the widget it was scheduled for. Left uncancelled, that Timer fires
      // later against an already-gone State (harmless, `key.currentState` is null by then) but
      // still counts as "pending" — flutter_test asserts none survive a test, so leaving this
      // out broke every existing test whose own teardown didn't happen to outlive the toast's
      // 3.5s default duration.
      onDisposed: () {
        if (identical(_currentToast, entry)) {
          _currentToastTimer?.cancel();
          _currentToastTimer = null;
          _currentToast = null;
        }
      },
    ),
  );

  overlay.insert(entry);
  _currentToast = entry;
  _currentToastTimer = Timer(duration, () => key.currentState?.dismiss());
}

void _dismissCurrentToast() {
  _currentToastTimer?.cancel();
  _currentToastTimer = null;
  _currentToast?.remove();
  _currentToast = null;
}

// ══════════════════════════════════════════════════════════════════════════════
// _ToastCard
// ══════════════════════════════════════════════════════════════════════════════

class _ToastCard extends StatefulWidget {
  const _ToastCard({
    super.key,
    required this.message,
    required this.tone,
    this.actionLabel,
    this.onAction,
    required this.onDismissed,
    required this.onDisposed,
  });

  final String message;
  final ToastTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Called once the exit animation finishes — removes this entry from the overlay. Also what a
  /// swipe-to-dismiss drives, through [dismiss].
  final VoidCallback onDismissed;

  /// Called unconditionally from [State.dispose] — see the call site's own doc comment for why
  /// this exists alongside [onDismissed] rather than instead of it.
  final VoidCallback onDisposed;

  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  bool _dismissing = false;
  bool _entranceStarted = false;

  // Distinct from `widget.key` (the GlobalKey showAppToast uses to drive dismiss()) — Dismissible
  // needs its own Key, and reusing the same GlobalKey for two widgets in the same tree throws a
  // duplicate-GlobalKey error.
  final _dismissibleKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    final curved = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _fade = curved;
    _slide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(curved);
  }

  // MediaQuery.of needs an established inherited-widget dependency, which isn't safe to read in
  // initState (throws — dependOnInheritedWidgetOfExactType before initState completes). This runs
  // right after, with the same one-shot guard so a later dependency change (e.g. the OS setting
  // itself flips mid-toast) doesn't replay the entrance.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entranceStarted) return;
    _entranceStarted = true;
    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    widget.onDisposed();
    _controller.dispose();
    super.dispose();
  }

  /// Reverses the entrance animation, then tells the overlay to remove this entry. Public (not
  /// just triggered by the auto-dismiss timer) so a swipe can drive the same exit.
  Future<void> dismiss() async {
    if (_dismissing) return;
    _dismissing = true;
    if (!MediaQuery.of(context).disableAnimations) {
      await _controller.reverse();
    }
    widget.onDismissed();
  }

  ({Color accent, Color accentBg, IconData icon}) _toneStyle(AppPalette p) => switch (widget.tone) {
    ToastTone.success => (
      accent: p.green,
      accentBg: p.green.withAlpha(31),
      icon: LucideIcons.checkCircle2,
    ),
    ToastTone.warning => (
      accent: p.amber,
      accentBg: p.amber.withAlpha(31),
      icon: LucideIcons.alertTriangle,
    ),
    ToastTone.error => (accent: p.red, accentBg: p.red.withAlpha(31), icon: LucideIcons.xCircle),
    ToastTone.info => (
      accent: AppColors.Y,
      accentBg: AppColors.Y.withAlpha(31),
      icon: LucideIcons.alertCircle,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final style = _toneStyle(context.colors);
    // Used to skip navClearance's 74px on the theory that a brief toast "slightly overlapping"
    // the floating nav pill on root-tab screens was a smaller cost than dead space on the
    // full-screen routes that have no nav. In practice the overlap wasn't slight: both this card
    // and the nav pill are translucent Vetro glass, so stacking them doesn't dim one behind the
    // other — it blurs two glass panels together and the toast's text becomes unreadable. A few
    // extra px of empty margin under the toast on a nav-less route is a far smaller cost than
    // that, so this always clears the nav's full height now.
    final bottomInset = context.navClearance;

    return Positioned(
      left: AppSpacing.pagePadding,
      right: AppSpacing.pagePadding,
      bottom: bottomInset,
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: Dismissible(
            key: _dismissibleKey,
            direction: DismissDirection.horizontal,
            onDismissed: (_) => widget.onDismissed(),
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.base,
                  vertical: AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  border: Border.all(color: context.colors.borderLight),
                  borderRadius: AppRack.freeShape,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(46),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: style.accentBg, shape: BoxShape.circle),
                      child: Icon(style.icon, size: 16, color: style.accent),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: context.colors.ink,
                          height: 1.3,
                        ),
                      ),
                    ),
                    if (widget.actionLabel != null && widget.onAction != null) ...[
                      const SizedBox(width: 4),
                      AppTappable(
                        onTap: widget.onAction,
                        borderRadius: BorderRadius.circular(8),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                        child: Text(
                          widget.actionLabel!,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: style.accent,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
