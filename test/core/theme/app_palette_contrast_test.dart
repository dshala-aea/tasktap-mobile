import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

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
  group('AppPalette AA contrast — light', () {
    test('ink clears 4.5:1 on bg2', () {
      expect(_contrast(AppPalette.light.ink, AppPalette.light.bg2), greaterThanOrEqualTo(4.5));
    });
    test('inkMuted clears 4.5:1 on bg2', () {
      expect(_contrast(AppPalette.light.inkMuted, AppPalette.light.bg2), greaterThanOrEqualTo(4.5));
    });
    test('inkMuted clears 4.5:1 on surface', () {
      expect(_contrast(AppPalette.light.inkMuted, AppPalette.light.surface), greaterThanOrEqualTo(4.5));
    });
    test('brandOn clears 4.5:1 on the brand accent (0xFFC03221)', () {
      expect(_contrast(AppPalette.light.brandOn, const Color(0xFFC03221)), greaterThanOrEqualTo(4.5));
    });
    test('shadow and shadowInset are empty — DESIGN.md bans floating-card shadows', () {
      expect(AppPalette.light.shadow, isEmpty);
      expect(AppPalette.light.shadowInset, isEmpty);
    });
  });

  group('AppPalette AA contrast — dark', () {
    test('ink clears 4.5:1 on bg2', () {
      expect(_contrast(AppPalette.dark.ink, AppPalette.dark.bg2), greaterThanOrEqualTo(4.5));
    });
    test('inkMuted clears 4.5:1 on bg2', () {
      expect(_contrast(AppPalette.dark.inkMuted, AppPalette.dark.bg2), greaterThanOrEqualTo(4.5));
    });
    test('brandOn clears 4.5:1 on the brand accent (0xFFC03221)', () {
      expect(_contrast(AppPalette.dark.brandOn, const Color(0xFFC03221)), greaterThanOrEqualTo(4.5));
    });
    test('shadow and shadowInset are empty — DESIGN.md bans floating-card shadows', () {
      expect(AppPalette.dark.shadow, isEmpty);
      expect(AppPalette.dark.shadowInset, isEmpty);
    });
  });
}
