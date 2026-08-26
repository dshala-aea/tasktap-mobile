// dart format width=100
import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_vetro_palette.dart';

/// A translucent, blurred surface — Vetro's one material primitive.
///
/// Hides the three things every glass surface in the system needs together (a backdrop blur, a
/// tinted fill over it, a hairline edge) behind a constructor a call site can read in one line.
/// Nothing here decides *which* colours to use — [fill]/[border] default to the current
/// `context.vetro` palette, but a screen that must stay a fixed colour regardless of the app theme
/// (Timbra, permanently dark — see `AppVetroColors`'s own doc comment) passes its own.
///
/// Deliberately not used for anything that repaints on a fast timer (a live clock, a pulsing
/// button): [BackdropFilter] re-samples everything behind it on every frame it's part of, and a
/// blur re-running every second for a control that doesn't need translucency in the first place
/// (Timbra's punch disc is a solid gradient) would be paying a real cost for nothing.
class VetroGlass extends StatelessWidget {
  const VetroGlass({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.padding,
    this.fill,
    this.border,
    this.blurSigma = AppVetroColors.blurSigma,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;

  /// Defaults to `context.vetro.glassFill` — pass explicitly for a surface that must not flip
  /// with the app theme (see class doc).
  final Color? fill;

  /// Defaults to `context.vetro.glassBorder`. See [fill].
  final Color? border;

  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    final v = context.vetro;
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: fill ?? v.glassFill,
            borderRadius: borderRadius,
            border: Border.all(color: border ?? v.glassBorder),
          ),
          child: child,
        ),
      ),
    );
  }
}
