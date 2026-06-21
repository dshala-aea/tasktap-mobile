import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';

/// Button variant.
///
/// - [primary]   — Y bg / DARK fg / SH shadow  (default)
/// - [secondary] — BG3 bg / MUTED fg
/// - [dark]      — DARK bg / INV fg / SH shadow
/// - [ghost]     — transparent bg / DARK fg
/// - [danger]    — REDSOFT bg / #c00 fg
enum AppButtonVariant { primary, secondary, dark, ghost, danger }

/// Button size.
///
/// - [lg] — vPad 14, hPad 24, fontSize 16, radius 20, iconSize 18
/// - [md] — vPad 11, hPad 20, fontSize 14, radius 18, iconSize 16  (default)
/// - [sm] — vPad 6,  hPad 14, fontSize 10, radius 10, iconSize 12
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
  })  : variant = AppButtonVariant.secondary,
        _expandLegacy = expand;

  const AppButton.dark({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.size = AppButtonSize.md,
    this.fullWidth,
  })  : variant = AppButtonVariant.dark,
        _expandLegacy = null;

  const AppButton.ghost({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.size = AppButtonSize.md,
    this.fullWidth,
  })  : variant = AppButtonVariant.ghost,
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
  })  : variant = AppButtonVariant.danger,
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

  double get _radius => switch (size) {
        AppButtonSize.lg => 20,
        AppButtonSize.md => 18,
        AppButtonSize.sm => 10,
      };

  double get _iconSize => switch (size) {
        AppButtonSize.lg => 18,
        AppButtonSize.md => 16,
        AppButtonSize.sm => 12,
      };

  // ── Colour tokens ────────────────────────────────────────────────────────

  Color get _bg => switch (variant) {
        AppButtonVariant.primary   => AppColors.Y,
        AppButtonVariant.secondary => AppColors.BG3,
        AppButtonVariant.dark      => AppColors.DARK,
        AppButtonVariant.ghost     => Colors.transparent,
        AppButtonVariant.danger    => AppColors.REDSOFT,
      };

  Color get _fg => switch (variant) {
        AppButtonVariant.primary   => AppColors.DARK,
        AppButtonVariant.secondary => AppColors.MUTED,
        AppButtonVariant.dark      => AppColors.INV,
        AppButtonVariant.ghost     => AppColors.DARK,
        AppButtonVariant.danger    => const Color(0xFFCC0000),
      };

  List<BoxShadow> get _shadows => switch (variant) {
        AppButtonVariant.primary => AppColors.SH,
        AppButtonVariant.dark    => AppColors.SH,
        _                        => const [],
      };

  @override
  Widget build(BuildContext context) {
    final textStyle = GoogleFonts.manrope(
      fontSize: _fontSize,
      fontWeight: FontWeight.w700,
      color: onPressed == null && !isLoading ? _fg.withAlpha(100) : _fg,
      letterSpacing: 0.1,
    );

    Widget content;
    if (isLoading) {
      content = SizedBox(
        width: _fontSize,
        height: _fontSize,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(_fg),
        ),
      );
    } else if (icon != null) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconTheme(
            data: IconThemeData(color: _fg, size: _iconSize),
            child: icon!,
          ),
          SizedBox(width: _hPad * 0.4),
          Text(label, style: textStyle),
        ],
      );
    } else {
      content = Text(label, style: textStyle);
    }

    final bgDisabled = _bg == Colors.transparent
        ? Colors.transparent
        : _bg.withAlpha(120);
    final fgDisabled = _fg.withAlpha(100);

    Widget button = DecoratedBox(
      decoration: BoxDecoration(
        color: onPressed != null || isLoading ? _bg : bgDisabled,
        borderRadius: BorderRadius.circular(_radius),
        boxShadow: onPressed != null ? _shadows : const [],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(_radius),
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(_radius),
          splashColor: _fg.withAlpha(30),
          highlightColor: _fg.withAlpha(15),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: _hPad,
              vertical: _vPad,
            ),
            child: DefaultTextStyle(
              style: textStyle.copyWith(
                color: onPressed == null && !isLoading ? fgDisabled : _fg,
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
