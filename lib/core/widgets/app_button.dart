import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

/// Button variant.
///
/// - [primary]   — flat AppColors.Y fill / white fg
/// - [secondary] — BG3 bg / MUTED fg
/// - [dark]      — DARK bg / INV fg
/// - [ghost]     — transparent bg / DARK fg
/// - [danger]    — REDSOFT bg / #c00 fg
enum AppButtonVariant { primary, secondary, dark, ghost, danger }

/// Button size.
///
/// - [lg] — vPad 14, hPad 24, fontSize 16, radius 10, iconSize 18
/// - [md] — vPad 11, hPad 20, fontSize 14, radius 8, iconSize 16  (default)
/// - [sm] — vPad 6,  hPad 14, fontSize 10, radius 6, iconSize 12
enum AppButtonSize { lg, md, sm }

/// TaskTap brand button — 5 variants × 3 sizes.
///
/// ```dart
/// AppButton(label: 'Salva');
/// AppButton(label: 'Salva', size: AppButtonSize.sm);
/// AppButton.secondary(label: 'Annulla');
/// AppButton.dark(label: 'Conferma');
/// AppButton.ghost(label: 'Salta');
/// AppButton.danger(label: 'Elimina');
/// ```
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.md,
    // Legacy alias
    bool? expand,
    this.fullWidth,
  }) : _expandLegacy = expand;

  const AppButton.secondary({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.size = AppButtonSize.md,
    bool? expand,
    this.fullWidth,
  }) : variant = AppButtonVariant.secondary,
       _expandLegacy = expand;

  const AppButton.dark({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.size = AppButtonSize.md,
    this.fullWidth,
  }) : variant = AppButtonVariant.dark,
       _expandLegacy = null;

  const AppButton.ghost({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.size = AppButtonSize.md,
    this.fullWidth,
  }) : variant = AppButtonVariant.ghost,
       _expandLegacy = null;

  const AppButton.danger({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.size = AppButtonSize.md,
    bool? expand,
    this.fullWidth,
  }) : variant = AppButtonVariant.danger,
       _expandLegacy = expand;

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final bool isLoading;
  final AppButtonVariant variant;
  final AppButtonSize size;

  /// Stretch button to full available width.
  final bool? fullWidth;

  /// Legacy [expand] parameter — kept for backward compat with existing call sites.
  // ignore: unused_field
  final bool? _expandLegacy;

  bool get _isFullWidth => fullWidth ?? (_expandLegacy ?? _defaultFullWidth);

  bool get _defaultFullWidth => switch (variant) {
    AppButtonVariant.ghost => false,
    _ => true,
  };

  // ── Size tokens ──────────────────────────────────────────────────────────

  double get _vPad => switch (size) {
    AppButtonSize.lg => 14,
    AppButtonSize.md => 11,
    AppButtonSize.sm => 6,
  };

  double get _hPad => switch (size) {
    AppButtonSize.lg => 24,
    AppButtonSize.md => 20,
    AppButtonSize.sm => 14,
  };

  double get _fontSize => switch (size) {
    AppButtonSize.lg => 16,
    AppButtonSize.md => 14,
    AppButtonSize.sm => 10,
  };

  // Matches VetroButton's own two-tier scale (16 full-size, 12 compact) rather than a third,
  // independent radius set — a form still on AppButton and a Vetro screen next to it used to
  // round their buttons by two unrelated amounts.
  double get _radius => switch (size) {
    AppButtonSize.lg => 16,
    AppButtonSize.md => 16,
    AppButtonSize.sm => 12,
  };

  double get _iconSize => switch (size) {
    AppButtonSize.lg => 18,
    AppButtonSize.md => 16,
    AppButtonSize.sm => 12,
  };

  // ── Colour tokens ────────────────────────────────────────────────────────

  /// Solid fill for every variant, including [primary] — DESIGN.md has no gradient fills
  /// ("no glassy gradients"). [primary] is now a flat [AppColors.Y] fill, matching every other
  /// variant's flat-fill treatment.
  Color _bg(BuildContext context) => switch (variant) {
    AppButtonVariant.primary => AppColors.Y,
    AppButtonVariant.secondary => context.colors.bg3,
    AppButtonVariant.dark => context.colors.surfaceInverse,
    AppButtonVariant.ghost => Colors.transparent,
    AppButtonVariant.danger => context.colors.redSoft,
  };

  Color _fg(BuildContext context) => switch (variant) {
    AppButtonVariant.primary => Colors.white,
    AppButtonVariant.secondary => context.colors.inkMuted,
    AppButtonVariant.dark => context.colors.inkInverse,
    AppButtonVariant.ghost => context.colors.ink,
    // context.colors.red, not a fixed hex — the fixed value paired fine with redSoft in light
    // mode but measured ~1.96:1 in dark mode, far under the 4.5:1 AA floor; the themed token is
    // tuned against both themes already (it's the same red every other destructive label in the
    // app uses).
    AppButtonVariant.danger => context.colors.red,
  };

  // No shadow on primary/dark, deliberately. This button sits in normal page flow, not as a
  // floating overlay (compare AppFab, which stays shadowed because it genuinely floats above
  // content) — and every modern reference this session's design research checked (Linear, Vercel,
  // Stripe, Notion) reserves box-shadow for transient overlays, never a static in-flow control.
  // A soft shadow is also invisible outdoors in direct sun, which this app cannot afford to rely
  // on: the accent fill and the ink-on-accent contrast already carry the button with no shadow
  // needed at all.
  List<BoxShadow> _shadows(BuildContext context) => const [];

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: _fontSize,
      fontWeight: FontWeight.w700,
      color: onPressed == null && !isLoading ? _fg(context).withAlpha(100) : _fg(context),
      letterSpacing: 0.1,
    );

    Widget content;
    if (isLoading) {
      // Center, not a bare SizedBox: a full-width button hands the tree below it a *tight*
      // infinite-width constraint (from the `SizedBox(width: double.infinity)` at the bottom of
      // this method), and nothing between it and here loosens that constraint. A ConstrainedBox
      // (which is what SizedBox compiles to) enforces its own request within the incoming bounds
      // rather than overriding them — so the spinner's own "be exactly 16x16" was being clamped
      // into "be exactly as wide as the button," stretching a circle into an oval the width of
      // the screen. Center loosens the constraint back to loose-infinite, which is what a child
      // that wants its own intrinsic size actually needs.
      content = Center(
        child: SizedBox(
          width: _fontSize,
          height: _fontSize,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(_fg(context)),
          ),
        ),
      );
    } else if (icon != null) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconTheme(
            data: IconThemeData(color: _fg(context), size: _iconSize),
            child: icon!,
          ),
          SizedBox(width: _hPad * 0.4),
          // Flexible, not a bare Text: an icon plus a two-word label ("Timbra cantiere") in a
          // half-width Expanded slot overflowed its render box with no wrap boundary — a real
          // RenderFlex overflow on a real device, not a hypothetical one. Ellipsis over a second
          // line: this Row has no height budget for a wrapped label.
          Flexible(
            child: Text(
              label,
              style: textStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    } else {
      content = Text(label, style: textStyle, maxLines: 1, overflow: TextOverflow.ellipsis);
    }

    final bgDisabled = _bg(context) == Colors.transparent
        ? Colors.transparent
        : _bg(context).withAlpha(120);
    final fgDisabled = _fg(context).withAlpha(100);

    final enabled = onPressed != null || isLoading;
    Widget button = DecoratedBox(
      decoration: BoxDecoration(
        color: enabled ? _bg(context) : bgDisabled,
        borderRadius: BorderRadius.circular(_radius),
        boxShadow: onPressed != null ? _shadows(context) : const [],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(_radius),
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(_radius),
          splashColor: _fg(context).withAlpha(30),
          highlightColor: _fg(context).withAlpha(15),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: _hPad, vertical: _vPad),
            child: DefaultTextStyle(
              style: textStyle.copyWith(
                color: onPressed == null && !isLoading ? fgDisabled : _fg(context),
              ),
              child: content,
            ),
          ),
        ),
      ),
    );

    // ≥44pt minimum touch target (accessibility)
    button = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
      child: button,
    );

    if (!_isFullWidth) return button;
    return SizedBox(width: double.infinity, child: button);
  }
}
