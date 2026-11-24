// ignore_for_file: constant_identifier_names
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_colors.dart';

/// The app accent derived from a tenant's brand colour, plus the stamp-red fallback.
///
/// A tenant colour is applied only when it clears [_minRatio] (WCAG, raw/unrounded) against each
/// of the three light surfaces (white, sheet, desk); otherwise [fromHex] returns null and callers
/// fall back to [stampRed]. See the tenant-colour plan, "Global Constraints", for the algorithm.
///
/// This file deliberately does not import `app_palette.dart`: the palette will import this file,
/// so [stampRed] is built from [AppColors] constants and literals that equal the palette's values.
@immutable
class AccentScheme {
  const AccentScheme({
    required this.fill,
    required this.fillDark,
    required this.fillSoft,
    required this.brandOn,
    required this.inkLight,
    required this.inkDark,
    required this.fillOnDark,
    required this.brandOnDark,
  });

  /// The accent as a fill (light theme).
  final Color fill;

  /// [fill] at HSL lightness x 0.85 — pressed/gradient-adjacent states.
  final Color fillDark;

  /// [fill] at alpha 0x33.
  final Color fillSoft;

  /// Text/icon on [fill] in the light theme.
  final Color brandOn;

  /// The accent as text/icon on paper (light theme).
  final Color inkLight;

  /// The accent as text/icon on the dark background (>= 4.5:1 on `#1E1F24`).
  final Color inkDark;

  /// The accent as a fill in the dark theme (>= 3:1 on `#1E1F24`).
  final Color fillOnDark;

  /// Text/icon on [fillOnDark]: the better of `#FBF9F4` / `#1E1F24`.
  final Color brandOnDark;

  /// Today's stamp red. Values equal `AppPalette.light` / `AppPalette.dark` (pinned by a test).
  static const AccentScheme stampRed = AccentScheme(
    fill: AppColors.Y,
    fillDark: AppColors.YDark,
    fillSoft: AppColors.YSoft,
    brandOn: AppColors.INV,
    inkLight: AppColors.Y,
    inkDark: Color(0xFFF0736E),
    fillOnDark: AppColors.Y,
    brandOnDark: AppColors.INV,
  );

  static const double _minRatio = 4.5;
  static const _white = _Rgb(0xFF, 0xFF, 0xFF);
  static const _sheet = _Rgb(0xFB, 0xF9, 0xF4);
  static const _desk = _Rgb(0xF1, 0xEE, 0xE7);
  static const _darkBg = _Rgb(0x1E, 0x1F, 0x24);

  /// The scheme for [hex] (6 digits, with or without `#`), or null when [hex] is null/invalid or
  /// fails the mobile rule.
  static AccentScheme? fromHex(String? hex) {
    final rgb = _parse(hex);
    if (rgb == null || _minContrast(rgb) < _minRatio) return null;

    final fill = rgb.toColor();
    final hsl = _toHsl(rgb);
    final fillDark = _fromHsl(hsl.h, hsl.s, hsl.l * 0.85).toColor();
    final fillSoft = fill.withAlpha(0x33);

    final inkDark = _lighten(rgb, 4.5);
    final fillOnDark = _lighten(rgb, 3.0);
    final onDarkFill = fillOnDark.toColor();
    final brandOnDark = _contrast(_sheet, fillOnDark) >= _contrast(_darkBg, fillOnDark)
        ? _sheet
        : _darkBg;

    return AccentScheme(
      fill: fill,
      fillDark: fillDark,
      fillSoft: fillSoft,
      brandOn: AppColors.INV,
      inkLight: fill,
      inkDark: inkDark.toColor(),
      fillOnDark: onDarkFill,
      brandOnDark: brandOnDark.toColor(),
    );
  }

  /// The rule alone: the minimum contrast of [hex] over white, sheet and desk (raw, unrounded).
  /// NaN when [hex] is invalid.
  static double minContrast(String hex) {
    final rgb = _parse(hex);
    return rgb == null ? double.nan : _minContrast(rgb);
  }

  static double _minContrast(_Rgb c) =>
      math.min(_contrast(c, _white), math.min(_contrast(c, _sheet), _contrast(c, _desk)));

  static final RegExp _hexPattern = RegExp(r'^#?([0-9a-fA-F]{6})$');

  static _Rgb? _parse(String? hex) {
    if (hex == null) return null;
    final m = _hexPattern.firstMatch(hex);
    if (m == null) return null;
    final v = int.parse(m.group(1)!, radix: 16);
    return _Rgb((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF);
  }

  static double _channel(int v) {
    final c = v / 255;
    return c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  static double _luminance(_Rgb c) =>
      0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

  static double _contrast(_Rgb a, _Rgb b) {
    final la = _luminance(a);
    final lb = _luminance(b);
    final hi = math.max(la, lb);
    final lo = math.min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
  }

  /// [rgb] itself if it already clears [target] on the dark background; otherwise the same hue and
  /// saturation with lightness `l0 + 0.01 * step` (step 1..100, from the ORIGINAL lightness)
  /// until it does. Falls through to the last step (lightness capped at 1) if none does.
  static _Rgb _lighten(_Rgb rgb, double target) {
    if (_contrast(rgb, _darkBg) >= target) return rgb;
    final hsl = _toHsl(rgb);
    var candidate = rgb;
    for (var step = 1; step <= 100; step++) {
      candidate = _fromHsl(hsl.h, hsl.s, math.min(1.0, hsl.l + 0.01 * step));
      if (_contrast(candidate, _darkBg) >= target) return candidate;
    }
    return candidate;
  }

  static _Hsl _toHsl(_Rgb c) {
    final r = c.r / 255;
    final g = c.g / 255;
    final b = c.b / 255;
    final mx = math.max(r, math.max(g, b));
    final mn = math.min(r, math.min(g, b));
    final l = (mx + mn) / 2;
    if (mx == mn) return _Hsl(0, 0, l);
    final d = mx - mn;
    final s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
    double h;
    if (mx == r) {
      h = (g - b) / d + (g < b ? 6 : 0);
    } else if (mx == g) {
      h = (b - r) / d + 2;
    } else {
      h = (r - g) / d + 4;
    }
    return _Hsl(h / 6, s, l);
  }

  static double _hue(double p, double q, double t) {
    var x = t;
    if (x < 0) x += 1;
    if (x > 1) x -= 1;
    if (x < 1 / 6) return p + (q - p) * 6 * x;
    if (x < 1 / 2) return q;
    if (x < 2 / 3) return p + (q - p) * (2 / 3 - x) * 6;
    return p;
  }

  static int _byte(double x) => (x * 255 + 0.5).floor().clamp(0, 255).toInt();

  static _Rgb _fromHsl(double h, double s, double l) {
    if (s == 0) {
      final v = _byte(l);
      return _Rgb(v, v, v);
    }
    final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    final p = 2 * l - q;
    return _Rgb(
      _byte(_hue(p, q, h + 1 / 3)),
      _byte(_hue(p, q, h)),
      _byte(_hue(p, q, h - 1 / 3)),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AccentScheme &&
      other.fill == fill &&
      other.fillDark == fillDark &&
      other.fillSoft == fillSoft &&
      other.brandOn == brandOn &&
      other.inkLight == inkLight &&
      other.inkDark == inkDark &&
      other.fillOnDark == fillOnDark &&
      other.brandOnDark == brandOnDark;

  @override
  int get hashCode =>
      Object.hash(fill, fillDark, fillSoft, brandOn, inkLight, inkDark, fillOnDark, brandOnDark);
}

class _Rgb {
  const _Rgb(this.r, this.g, this.b);
  final int r;
  final int g;
  final int b;
  Color toColor() => Color.fromARGB(0xFF, r, g, b);
}

class _Hsl {
  const _Hsl(this.h, this.s, this.l);
  final double h;
  final double s;
  final double l;
}
