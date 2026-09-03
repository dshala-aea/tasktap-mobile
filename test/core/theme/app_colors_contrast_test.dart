import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/app_colors.dart';

// WCAG relative luminance: linearize each 0.0-1.0 sRGB channel (Color.r/.g/.b are already
// 0.0-1.0 doubles as of the Flutter Color API this app's pinned SDK ships), then weight-sum.
double _linearize(double v) => v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _linearize(c.r) + 0.7152 * _linearize(c.g) + 0.0722 * _linearize(c.b);

double _contrast(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('AppColors AA contrast on the new paper surfaces', () {
    test('MUTED clears 4.5:1 on BG1 (desk)', () {
      expect(_contrast(AppColors.MUTED, AppColors.BG1), greaterThanOrEqualTo(4.5));
    });

    test('MUTED clears 4.5:1 on SHEET', () {
      expect(_contrast(AppColors.MUTED, AppColors.SHEET), greaterThanOrEqualTo(4.5));
    });

    test('DARK (ink) clears 4.5:1 on BG1', () {
      expect(_contrast(AppColors.DARK, AppColors.BG1), greaterThanOrEqualTo(4.5));
    });

    test('Y (stamp red) clears 4.5:1 on BG1 when used as text/icon', () {
      expect(_contrast(AppColors.Y, AppColors.BG1), greaterThanOrEqualTo(4.5));
    });

    test('white clears 4.5:1 on Y (button foreground)', () {
      expect(_contrast(Colors.white, AppColors.Y), greaterThanOrEqualTo(4.5));
    });
  });
}
