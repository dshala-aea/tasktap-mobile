// ignore_for_file: constant_identifier_names

/// Vetro design-system tokens (2026-08-26 redesign), additive alongside [AppColors]/[AppPalette].
///
/// Cassetta is not being replaced app-wide — the redesign lands module by module, and an
/// already-shipped screen must keep rendering in Cassetta until its own turn comes. Vetro tokens
/// therefore live in their own file and their own [ThemeExtension], registered *alongside* [p] in
/// `buildAppTheme` rather than in place of it. A screen opts in by reading `context.vetro`; every
/// screen that hasn't been touched yet keeps reading `context.colors` and is unaffected.
///
/// Two tiers, mirroring the split [AppColors]/[AppPalette] already use for the same reason:
///
/// - [AppVetroColors] — raw values for surfaces that are dark under *both* app themes (the
///   punch-clock screens; see [AppColors.punchGround]'s own doc comment for why those don't
///   belong in a flipping palette).
/// - [AppVetroPalette] — the flipping [ThemeExtension], for the light/dark Vetro screens later
///   modules will add (Tickets, Clienti, ...). Not exercised by module #1 — Timbra stays
///   permanently dark — but the interface future modules build on, decided already (module-by-
///   module rollout is the agreed plan, not a guess at future scope).
///
/// The `tint`/`tintStrong` pair is the *only* saturated colour in the system: it appears exactly
/// where something is active (the punch disc, a running clock, a selected tab) and nowhere else.
/// Everything else is near-monochrome ink/glass, the same discipline [AppColors.Y] already
/// documents for the one Cassetta accent — Vetro keeps that discipline, it just changes what the
/// one colour is and how it's rendered (gradient + blur rather than flat fill).
library;

import 'package:flutter/material.dart';

/// Raw Vetro values for surfaces that are dark under both themes. Same status as
/// [AppColors.punchGround]/[AppColors.stopLight] — do not read these from a widget on a surface
/// that flips with the app theme; use [AppVetroPalette] (via `context.vetro`) there instead.
abstract final class AppVetroColors {
  /// Indigo — the "something is active" colour. Gradient light stop.
  ///
  /// Exactly the value proven in the Timbra glare comparison (glass-vs-flat, both accepted): full
  /// gradient/glow/blur was chosen with this colour under a simulated direct-sunlight wash, so it
  /// is not a fresh, untested pick for the one screen that has to survive that condition.
  static const Color tint = Color(0xFF4F6BFF);

  /// Violet — gradient dark stop. Paired with [tint] as `LinearGradient(colors: [tint, tintStrong])`.
  static const Color tintStrong = Color(0xFF8A5CF6);

  /// Glass fill on a permanently-dark ground: white at low alpha, meant to sit over
  /// [AppColors.punchGround] under a [BackdropFilter] blur (see `VetroGlass`). Not applied to the
  /// live clock or the primary punch disc — both rebuild every second on the pulse/clock timer,
  /// and neither needs translucency (they're solid gradient fills) — only to the secondary,
  /// static-between-taps controls (pause pill, sessions card).
  static const Color glassFillOnDark = Color(0x1AFFFFFF); // white, 10%

  /// Glass edge on a permanently-dark ground — a hairline, not a Cassetta-weight border.
  static const Color glassBorderOnDark = Color(0x26FFFFFF); // white, 15%

  /// Standard blur sigma for [VetroGlass]. One value, not per-surface — a system reads as one
  /// material only if every glass surface blurs by the same amount.
  static const double blurSigma = 20;

  // ── Status pairs, fixed dark-ground values ──────────────────────────────────
  //
  // Mirror [AppVetroPalette.dark]'s statusGood/Warn/Bad pairs exactly — same tint-on-tint
  // discipline (saturated colour in text/dot, that same hue at ~15-18% alpha behind it), just as
  // fixed constants because Timbra's ground never flips. Added for the Timbra hero-status
  // redesign, which needed an "on shift" badge and a promoted guard-blocked banner; before this
  // the only options on a permanently-dark screen were the flipping [AppVetroPalette] (wrong
  // variant risk) or raw [AppColors] semantic colours (a different, untested-on-this-ground
  // shade, and outside Vetro's tint/stop status vocabulary entirely).

  static const Color statusGood = Color(0xFF3DD866);
  static const Color statusGoodBg = Color(0x2934C759);
  static const Color statusWarn = Color(0xFFFFB238);
  static const Color statusWarnBg = Color(0x2EFF9F0A);
  static const Color statusBad = Color(0xFFFF6961);
  static const Color statusBadBg = Color(0x29FF453A);
}

/// The flipping half of the Vetro system — [ThemeExtension] for screens whose ground changes with
/// the app theme. See this file's own doc comment for why Timbra does not use this.
@immutable
class AppVetroPalette extends ThemeExtension<AppVetroPalette> {
  const AppVetroPalette({
    required this.tint,
    required this.tintStrong,
    required this.glassFill,
    required this.glassBorder,
    required this.hairline,
    required this.statusGood,
    required this.statusGoodBg,
    required this.statusWarn,
    required this.statusWarnBg,
    required this.statusBad,
    required this.statusBadBg,
  });

  /// The one accent — gradient light stop. See [AppVetroColors.tint].
  final Color tint;

  /// Gradient dark stop. See [AppVetroColors.tintStrong].
  final Color tintStrong;

  /// Glass card fill, under a [BackdropFilter] blur.
  final Color glassFill;

  /// Glass card edge — a hairline (8–15% alpha), never a solid Cassetta-weight border.
  final Color glassBorder;

  /// Divider weight for a Vetro screen — the same job [AppPalette.divider] does for Cassetta, at
  /// Vetro's much lower opacity (rows are told apart by an 8% line, not a filled border).
  final Color hairline;

  // ── Status — tint-on-tint badges, not solid fills ──────────────────────────
  //
  // A [statusGood]/[statusGoodBg] pair is always used together: text/dot in the saturated colour,
  // background in that same colour at ~12% alpha. Never pair [statusGood] with a plain white/ink
  // background — the whole point of a Vetro status badge is that its background carries the same
  // hue as its text.

  final Color statusGood;
  final Color statusGoodBg;
  final Color statusWarn;
  final Color statusWarnBg;
  final Color statusBad;
  final Color statusBadBg;

  /// Light Vetro — values as designed (indigo/violet on near-white glass).
  static const light = AppVetroPalette(
    tint: Color(0xFF4F6BFF),
    tintStrong: Color(0xFF8A5CF6),
    glassFill: Color(0xAEFFFFFF), // white, ~68%
    glassBorder: Color(0x99FFFFFF), // white, ~60%
    hairline: Color(0x14000000), // black, 8%
    statusGood: Color(0xFF248A3D),
    statusGoodBg: Color(0x1F34C759),
    statusWarn: Color(0xFFB36200),
    statusWarnBg: Color(0x24FF9F0A),
    statusBad: Color(0xFFFF3B30),
    statusBadBg: Color(0x1FFF3B30),
  );

  /// Dark Vetro — glass over a near-black ground rather than near-white.
  static const dark = AppVetroPalette(
    tint: Color(0xFF7C93FF),
    tintStrong: Color(0xFFA78BFA),
    glassFill: Color(0x33FFFFFF), // white, 20% — a light film over dark reads; 68% would not
    glassBorder: Color(0x40FFFFFF),
    hairline: Color(0x1FFFFFFF), // white, 12%
    statusGood: Color(0xFF3DD866),
    statusGoodBg: Color(0x2934C759),
    statusWarn: Color(0xFFFFB238),
    statusWarnBg: Color(0x2EFF9F0A),
    statusBad: Color(0xFFFF6961),
    statusBadBg: Color(0x29FF453A),
  );

  @override
  AppVetroPalette copyWith({
    Color? tint,
    Color? tintStrong,
    Color? glassFill,
    Color? glassBorder,
    Color? hairline,
    Color? statusGood,
    Color? statusGoodBg,
    Color? statusWarn,
    Color? statusWarnBg,
    Color? statusBad,
    Color? statusBadBg,
  }) {
    return AppVetroPalette(
      tint: tint ?? this.tint,
      tintStrong: tintStrong ?? this.tintStrong,
      glassFill: glassFill ?? this.glassFill,
      glassBorder: glassBorder ?? this.glassBorder,
      hairline: hairline ?? this.hairline,
      statusGood: statusGood ?? this.statusGood,
      statusGoodBg: statusGoodBg ?? this.statusGoodBg,
      statusWarn: statusWarn ?? this.statusWarn,
      statusWarnBg: statusWarnBg ?? this.statusWarnBg,
      statusBad: statusBad ?? this.statusBad,
      statusBadBg: statusBadBg ?? this.statusBadBg,
    );
  }

  @override
  AppVetroPalette lerp(ThemeExtension<AppVetroPalette>? other, double t) {
    if (other is! AppVetroPalette) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppVetroPalette(
      tint: c(tint, other.tint),
      tintStrong: c(tintStrong, other.tintStrong),
      glassFill: c(glassFill, other.glassFill),
      glassBorder: c(glassBorder, other.glassBorder),
      hairline: c(hairline, other.hairline),
      statusGood: c(statusGood, other.statusGood),
      statusGoodBg: c(statusGoodBg, other.statusGoodBg),
      statusWarn: c(statusWarn, other.statusWarn),
      statusWarnBg: c(statusWarnBg, other.statusWarnBg),
      statusBad: c(statusBad, other.statusBad),
      statusBadBg: c(statusBadBg, other.statusBadBg),
    );
  }
}

/// `context.vetro` — the Vetro palette for the theme this widget is under.
extension AppVetroPaletteContext on BuildContext {
  /// Falls back to [AppVetroPalette.light], same reasoning as [AppPaletteContext.colors]: a
  /// widget test that pumps a bare `MaterialApp` registers no extension, and rendering in the
  /// wrong colours is a better test failure than an exception.
  AppVetroPalette get vetro => Theme.of(this).extension<AppVetroPalette>() ?? AppVetroPalette.light;
}
