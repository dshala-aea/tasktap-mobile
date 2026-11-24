import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/accent_scheme.dart';
import 'package:tasktap_mobile/core/theme/app_colors.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

const _darkBg = Color(0xFF1E1F24);
const _sheet = Color(0xFFFBF9F4);

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('rule vectors', () {
    // hex, min ratio over white/sheet/desk, applied?
    const vectors = <(String, double, bool)>[
      ('#C03221', 4.87, true),
      ('#0000FF', 7.42, true),
      ('#1565C0', 4.96, true),
      ('#000000', 18.12, true),
      ('#2E7D32', 4.43, false),
      ('#757575', 3.98, false),
      ('#808080', 3.41, false),
      ('#E65100', 3.27, false),
      ('#FFD700', 1.21, false),
      ('#FFF10E', 1.02, false),
    ];
    for (final (hex, ratio, applied) in vectors) {
      test('$hex -> $ratio, applied=$applied', () {
        expect(AccentScheme.minContrast(hex), closeTo(ratio, 0.01));
        expect(AccentScheme.fromHex(hex) == null, !applied);
      });
    }
  });

  group('parsing', () {
    test('no leading # is accepted and equal', () {
      expect(AccentScheme.fromHex('c03221'), isNotNull);
      expect(AccentScheme.fromHex('c03221'), AccentScheme.fromHex('#C03221'));
    });
    test('invalid input yields null', () {
      expect(AccentScheme.fromHex('#fff'), isNull);
      expect(AccentScheme.fromHex(''), isNull);
      expect(AccentScheme.fromHex('red'), isNull);
      expect(AccentScheme.fromHex(null), isNull);
      expect(AccentScheme.minContrast('red').isNaN, isTrue);
    });
  });

  group('#C03221', () {
    final s = AccentScheme.fromHex('#C03221')!;
    test('light derivations', () {
      expect(s.fill, const Color(0xFFC03221));
      expect(s.fillSoft, const Color(0x33C03221));
      expect(s.brandOn, AppColors.INV);
      expect(s.inkLight, s.fill);
    });
  });

  group('dark derivations', () {
    for (final hex in ['#0000FF', '#000000', '#1565C0']) {
      test('$hex clears the dark-theme thresholds', () {
        final s = AccentScheme.fromHex(hex)!;
        expect(_contrast(s.inkDark, _darkBg), greaterThanOrEqualTo(4.5));
        expect(_contrast(s.fillOnDark, _darkBg), greaterThanOrEqualTo(3.0));
        expect(s.brandOnDark == _sheet || s.brandOnDark == _darkBg, isTrue);
        final other = s.brandOnDark == _sheet ? _darkBg : _sheet;
        expect(
          _contrast(s.brandOnDark, s.fillOnDark),
          greaterThanOrEqualTo(_contrast(other, s.fillOnDark)),
        );
      });
    }

    test('#000000 is lifted on dark and fillDark is not lighter than fill', () {
      final s = AccentScheme.fromHex('#000000')!;
      expect(s.fillOnDark, isNot(s.fill));
      expect(s.fillDark.computeLuminance(), lessThanOrEqualTo(s.fill.computeLuminance()));
    });

    test('lightening steps from the original lightness: l0 + 0.01 * step', () {
      // Hand-computed with python3 using the plan's algorithm (HSL, l0 + 0.01*step, half-up
      // rounding). #0000FF has l0 = 0.5; first step clearing 4.5:1 on #1E1F24 is step 24
      // (l = 0.74) -> #7A7AFF; first step clearing 3:1 is step 16 (l = 0.66) -> #5252FF.
      final s = AccentScheme.fromHex('#0000FF')!;
      expect(s.inkDark, const Color(0xFF7A7AFF));
      expect(s.fillOnDark, const Color(0xFF5252FF));
      expect(s.fillDark, const Color(0xFF0000D9));
    });

    test('#1565C0 lifts to hand-computed values (python3, same algorithm)', () {
      final s = AccentScheme.fromHex('#1565C0')!;
      expect(s.inkDark, const Color(0xFF3488E9));
      expect(s.fillOnDark, const Color(0xFF166AC9));
    });
  });

  group('stampRed', () {
    test('equals today\'s palette values', () {
      const s = AccentScheme.stampRed;
      expect(s.fill, AppColors.Y);
      expect(s.fillDark, AppColors.YDark);
      expect(s.fillSoft, AppColors.YSoft);
      expect(s.brandOn, AppPalette.light.brandOn);
      expect(s.inkLight, AppPalette.light.accentInk);
      expect(s.inkDark, AppPalette.dark.accentInk);
      expect(s.fillOnDark, AppColors.Y);
      expect(s.brandOnDark, AppPalette.dark.brandOn);
    });
  });
}
