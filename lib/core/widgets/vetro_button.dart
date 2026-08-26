// dart format width=100
import 'package:flutter/material.dart';

import '../theme/app_vetro_palette.dart';

/// Vetro's primary action — gradient fill, soft shadow, white ink. Additive alongside [AppButton],
/// not a replacement: [AppButton]'s own doc comment documents a deliberate, tested no-shadow
/// stance (a soft shadow is invisible outdoors, so the app "cannot afford to rely on" one) — real
/// reasoning, not stale, and this widget knowingly diverges from it for Vetro screens rather than
/// overriding [AppButton] itself and dragging every not-yet-redesigned screen along with it.
///
/// Interface intentionally mirrors [AppButton]'s primary path (label/icon/isLoading/onPressed) so
/// a call site reads the same either way — only the fill decoration differs.
class VetroButton extends StatelessWidget {
  const VetroButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.fullWidth = true,
    this.gradientColors,
    this.compact = false,
    this.secondary = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final bool isLoading;
  final bool fullWidth;

  /// Overrides the default `[tint, tintStrong]` fill — e.g. a destructive/"ending" action reusing
  /// [AppColors.stopLight]/[AppColors.stopDark], the same pair [TimbraScreen]'s punch button uses
  /// for its own "ending" state, rather than inventing a second red family. Ignored when
  /// [secondary] is true — a tonal fill has no gradient to override.
  final List<Color>? gradientColors;

  /// The inline, secondary-context size — a timer bar's Avvia/Ferma, a status row's small action.
  /// Same gradient/shadow language, smaller padding and type, never [fullWidth] regardless of the
  /// flag (an inline control next to other content, not a standalone action).
  final bool compact;

  /// The lower-emphasis action — tint at ~12% alpha, tint text, no gradient/shadow/blur. Same
  /// tint-on-tint language [AppVetroPalette]'s status badges already use, not a borrowed Material
  /// "outline button" convention. For a genuinely secondary action next to a primary [VetroButton]
  /// — was the gap that left "Timbra cantiere" (ticket_detail_screen.dart) and "Genera
  /// pianificazione" (admin_contract_detail_screen.dart) on the old `AppButton(variant: secondary)`
  /// with no Vetro equivalent to swap to.
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    final v = context.vetro;
    final enabled = onPressed != null && !isLoading;
    final colors = gradientColors ?? [v.tint, v.tintStrong];
    final radius = compact ? 12.0 : 16.0;
    final contentColor = secondary ? v.tint : Colors.white;

    final textStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: compact ? 13 : 16,
      fontWeight: FontWeight.w700,
      color: contentColor,
      letterSpacing: 0.1,
    );

    Widget content;
    if (isLoading) {
      content = SizedBox(
        width: compact ? 14 : 18,
        height: compact ? 14 : 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: contentColor),
      );
    } else if (icon != null) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconTheme(
            data: IconThemeData(color: contentColor, size: compact ? 14 : 18),
            child: icon!,
          ),
          SizedBox(width: compact ? 6 : 10),
          Flexible(child: Text(label, style: textStyle, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      );
    } else {
      content = Text(label, style: textStyle, maxLines: 1, overflow: TextOverflow.ellipsis);
    }

    Widget button = DecoratedBox(
      decoration: secondary
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              color: v.tint.withAlpha(31),
            )
          : BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors,
              ),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: colors.first.withAlpha(110),
                        blurRadius: compact ? 14 : 24,
                        offset: Offset(0, compact ? 6 : 12),
                      ),
                    ]
                  : const [],
            ),
      child: Opacity(
        opacity: enabled || isLoading ? 1 : 0.45,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(radius),
          child: InkWell(
            onTap: isLoading ? null : onPressed,
            borderRadius: BorderRadius.circular(radius),
            splashColor: contentColor.withAlpha(secondary ? 20 : 30),
            highlightColor: contentColor.withAlpha(secondary ? 10 : 15),
            child: Padding(
              padding: compact
                  ? const EdgeInsets.symmetric(horizontal: 14, vertical: 9)
                  : const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
              child: Center(widthFactor: 1, heightFactor: 1, child: content),
            ),
          ),
        ),
      ),
    );

    button = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
      child: button,
    );

    if (!fullWidth || compact) return button;
    return SizedBox(width: double.infinity, child: button);
  }
}
