import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tasktap_mobile/core/theme/app_colors.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_theme.dart';

/// WCAG relative luminance, then the 4.5:1 style ratio.
double _luminance(Color c) {
  double channel(double v) {
    v /= 255;
    return v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(c.r * 255) + 0.7152 * channel(c.g * 255) + 0.0722 * channel(c.b * 255);
}

double contrast(Color a, Color b) {
  // Flatten any alpha in the foreground over the background first. `AppColors.onDarkMuted` is 75%
  // white; comparing its raw channels would report a contrast nobody actually sees.
  final la = _luminance(Color.alphaBlend(a, b)), lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  // buildAppTheme() builds a TextTheme through GoogleFonts, which otherwise tries to fetch the
  // font over the network and fails the test on a build machine with no internet — and would
  // fail it for the wrong reason on one with internet, by being slow.
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('the light palette is exactly what shipped', () {
    /// The migration renamed ~460 call sites from `AppColors.X` to `context.colors.y`. The one
    /// thing that must not have happened is a value changing along the way: light mode is what
    /// every user sees today and what every screenshot and manual check was done against.
    test('every token still holds its old constant', () {
      const p = AppPalette.light;

      expect(p.ink, AppColors.DARK);
      expect(p.inkMuted, AppColors.MUTED);
      expect(p.inkFaint, AppColors.FG2);
      expect(p.inkDisabled, AppColors.DIS);
      expect(p.inkInverse, AppColors.WHITE);
      expect(p.surface, AppColors.WHITE);
      expect(p.surfaceInverse, AppColors.DARK);
      expect(p.bg1, AppColors.BG1);
      expect(p.bg2, AppColors.BG2);
      expect(p.bg3, AppColors.BG3);
      expect(p.bg4, AppColors.BG4);
      expect(p.borderLight, AppColors.BL);
      expect(p.borderMedium, AppColors.BM);
      expect(p.borderStrong, AppColors.BS);
      expect(p.divider, AppColors.DIV);
      expect(p.amber, AppColors.AMBER);
      expect(p.green, AppColors.GREEN);
      expect(p.blue, AppColors.BLUE);
      expect(p.cyan, AppColors.CYAN);
      expect(p.red, AppColors.RED);
      expect(p.redSoft, AppColors.REDSOFT);
      expect(p.brandOn, AppColors.DARK);
      expect(p.shadow, AppColors.SH);
    });
  });

  group('the dark palette is readable', () {
    const d = AppPalette.dark;

    /// The failure this catches is the one that makes a dark theme worthless: keeping a hue that
    /// was picked to clear 4.5:1 on white. #2563EB on #1A1A1A is 2.4:1 — present, coloured, and
    /// unreadable.
    test('text clears AA on the screen background', () {
      expect(contrast(d.ink, d.bg2), greaterThan(4.5));
      expect(contrast(d.inkMuted, d.bg2), greaterThan(4.5));
      expect(contrast(d.inkFaint, d.bg2), greaterThan(4.5));
    });

    test('text clears AA on a card', () {
      expect(contrast(d.ink, d.surface), greaterThan(4.5));
      expect(contrast(d.inkMuted, d.surface), greaterThan(4.5));
    });

    test('semantic colours clear AA rather than staying their light-theme selves', () {
      for (final entry in {
        'blue': d.blue,
        'green': d.green,
        'red': d.red,
        'amber': d.amber,
        'cyan': d.cyan,
      }.entries) {
        expect(
          contrast(entry.value, d.bg2),
          greaterThan(4.5),
          reason: '${entry.key} is unreadable on the dark background',
        );
      }
    });

    /// Both halves of the pair flip together, or a chip inverts into invisibility.
    test('inverse ink reads on the inverse surface', () {
      expect(contrast(d.inkInverse, d.surfaceInverse), greaterThan(4.5));
      expect(
        contrast(AppPalette.light.inkInverse, AppPalette.light.surfaceInverse),
        greaterThan(4.5),
      );
    });

    /// Yellow does not flip — it is the brand — so what sits on it must not either.
    test('the brand pairing is identical in both themes', () {
      expect(d.brandOn, AppPalette.light.brandOn);
      expect(contrast(d.brandOn, AppColors.Y), greaterThan(4.5));
    });

    test('surfaces step apart enough to read as layers', () {
      expect(d.bg1.toARGB32(), isNot(d.bg2.toARGB32()));
      expect(
        contrast(d.surface, d.bg1),
        greaterThan(1.05),
        reason: 'a card indistinguishable from the page is not a card',
      );
    });
  });

  group('the theme carries the palette', () {
    // testWidgets, not test: building the theme constructs GoogleFonts styles, whose font load
    // resolves asynchronously. Outside a widget tester that lands in the test's zone as an
    // unhandled error rather than as a failure anyone can read.
    testWidgets('light and dark register the matching extension', (tester) async {
      expect(buildAppTheme().extension<AppPalette>(), AppPalette.light);
      expect(buildAppTheme(brightness: Brightness.dark).extension<AppPalette>(), AppPalette.dark);
    });

    /// The text styles no longer bake a colour, so this is where headings get theirs. If the
    /// `.apply()` is dropped they fall back to Material's near-black default and vanish in dark.
    testWidgets('text colour comes from the palette, in both themes', (tester) async {
      expect(buildAppTheme().textTheme.bodyMedium!.color, AppPalette.light.ink);
      expect(
        buildAppTheme(brightness: Brightness.dark).textTheme.bodyMedium!.color,
        AppPalette.dark.ink,
      );
      expect(
        buildAppTheme(brightness: Brightness.dark).textTheme.displayLarge!.color,
        AppPalette.dark.ink,
      );
    });

    testWidgets('context.colors resolves the theme it is under', (tester) async {
      late AppPalette seen;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(brightness: Brightness.dark),
          home: Builder(
            builder: (context) {
              seen = context.colors;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(seen, AppPalette.dark);
    });

    /// A bare MaterialApp registers no extension. Rendering in the wrong colours is a better
    /// failure for a widget test than a crash.
    testWidgets('falls back to light rather than throwing', (tester) async {
      late AppPalette seen;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              seen = context.colors;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(seen, AppPalette.light);
    });
  });

  group('ink on a permanently dark surface', () {
    // The app produced this bug four times: a CHARCOAL surface painted with a token that flips.
    // These assertions pin the reason the fixed pair exists, so nobody "simplifies" them away.
    test('the fixed pair clears AA on CHARCOAL', () {
      expect(contrast(AppColors.onDark, AppColors.CHARCOAL), greaterThan(4.5));
      expect(contrast(AppColors.onDarkMuted, AppColors.CHARCOAL), greaterThan(4.5));
    });

    test('onDarkMuted is subordinate to onDark, not merely different', () {
      expect(
        contrast(AppColors.onDarkMuted, AppColors.CHARCOAL),
        lessThan(contrast(AppColors.onDark, AppColors.CHARCOAL)),
      );
    });

    test('the light theme\'s muted ink is unusable there, which is the whole point', () {
      // 1.9:1. This was the label above the headline figure on the hours step.
      expect(contrast(AppPalette.light.inkMuted, AppColors.CHARCOAL), lessThan(3));
    });

    test('inkInverse flips, so it cannot serve a surface that does not', () {
      // Fine in light, near-black in dark — on a bar that is CHARCOAL either way.
      expect(contrast(AppPalette.light.inkInverse, AppColors.CHARCOAL), greaterThan(4.5));
      expect(contrast(AppPalette.dark.inkInverse, AppColors.CHARCOAL), lessThan(3));
    });
  });

  test('no screen opts out of the themed input decoration', () {
    // Forty-nine fields across ten files passed `border: OutlineInputBorder()` explicitly, which
    // overrides `inputDecorationTheme` — so the admin forms rendered Material's stock border with
    // Material's stock radius and colours, inside an app that had already themed all three. The
    // theme was correct the whole time; the fields were opting out of it.
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.readAsStringSync().contains('OutlineInputBorder()')) {
        offenders.add(entity.path.replaceAll(r'\', '/'));
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Let the field inherit inputDecorationTheme instead of passing a bare '
          'OutlineInputBorder(). Override only to say something the theme does not.',
    );
  });

  /// Colour that reaches a widget as a constant cannot respond to the theme. The exceptions are
  /// the brand yellow, which does not flip, and the surfaces that are fixed-dark under both
  /// themes — a hero, a coloured status dot — where a flipping token would be the bug.
  test('screens read colour from the theme, not from constants', () {
    const allowedTokens = {
      'Y', 'YSoft', 'YDark', 'CHARCOAL', 'WHITE',
      'statusBozza', 'onStatusBozza', 'statusInviato', 'onStatusInviato',
      'statusControllato', 'onStatusControllato', 'statusFatturato', 'onStatusFatturato',
      'statusAnnullato', 'onStatusAnnullato',
      // Alias of Y.
      'brand',
      // The dashboard hero's gradient: dark under both themes, so a flipping token would be
      // the bug. Its call site says so. (CHARCOAL is already above.)
      'DARK',
      // The timbratura screens' ground and their end-shift disc. Fixed-dark under both themes:
      // the punch clock is a full-bleed dark surface read at arm's length in a van cab, and it
      // stays dark when the app is in light mode. A palette token would invert it.
      //
      // `stopLight`/`stopDark` are the one danger red lightened and darkened. They are constants
      // rather than palette entries because they only ever appear on `punchGround`, which does
      // not flip — so there is no second theme for them to have a value in.
      'punchGround', 'stopLight', 'stopDark',
      // Ink for surfaces that are dark under both themes — a CHARCOAL bar, hero or panel. These
      // exist precisely because reaching for a flipping token there is the bug: see the contrast
      // group below, which pins why `inkMuted` cannot be used on CHARCOAL.
      'onDark', 'onDarkMuted',
    };

    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (path.startsWith('lib/core/theme/')) continue;

      for (final m in RegExp(r'AppColors\.(\w+)').allMatches(entity.readAsStringSync())) {
        if (!allowedTokens.contains(m.group(1))) offenders.add('$path → ${m.group(0)}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Use context.colors.* so the value follows the theme. If the surface underneath '
          'is fixed-dark in both themes, the constant is right — add its token to allowedTokens '
          'and say why at the call site.',
    );
  });
}
