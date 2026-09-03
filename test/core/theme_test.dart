import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/app_colors.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_theme.dart';
import 'package:tasktap_mobile/core/theme/app_vetro_palette.dart';
import 'package:tasktap_mobile/core/theme/status_colors.dart';

/// [statusColor]/[statusColorFromStato] now read the Vetro theme extension via [BuildContext], so
/// exercising them needs a pumped widget tree. A bare `MaterialApp` registers no
/// [AppVetroPalette] extension — `context.vetro` falls back to [AppVetroPalette.light] (see its
/// own doc comment), which is what these assertions check against.
Future<StatusColorPair> _pairFor(WidgetTester tester, String stato) async {
  late StatusColorPair pair;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          pair = statusColor(context, stato);
          return const SizedBox();
        },
      ),
    ),
  );
  return pair;
}

Future<StatusColorPair> _pairForStato(WidgetTester tester, ReportStato stato) async {
  late StatusColorPair pair;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          pair = statusColorFromStato(context, stato);
          return const SizedBox();
        },
      ),
    ),
  );
  return pair;
}

void main() {
  const v = AppVetroPalette.light;
  const p = AppPalette.light;
  final infoBg = v.tint.withAlpha(31);
  // google_fonts loads fonts asynchronously; using testWidgets gives us a
  // binding + fake-async environment so font-load callbacks don't escape.
  group('buildAppTheme', () {
    testWidgets('returns a valid ThemeData', (tester) async {
      final theme = buildAppTheme();
      expect(theme, isA<ThemeData>());
    });

    testWidgets('primary color is brand accent Y', (tester) async {
      final theme = buildAppTheme();
      expect(theme.colorScheme.primary, equals(AppColors.Y));
    });

    testWidgets('onPrimary color is DARK for contrast', (tester) async {
      final theme = buildAppTheme();
      expect(theme.colorScheme.onPrimary, equals(AppColors.DARK));
    });

    testWidgets('brightness is light', (tester) async {
      final theme = buildAppTheme();
      expect(theme.colorScheme.brightness, equals(Brightness.light));
    });

    testWidgets('useMaterial3 is true', (tester) async {
      final theme = buildAppTheme();
      expect(theme.useMaterial3, isTrue);
    });

    testWidgets('error color is set', (tester) async {
      final theme = buildAppTheme();
      expect(theme.colorScheme.error, equals(AppColors.error));
    });
  });

  group('statusColor (Vetro tokens, context-aware)', () {
    testWidgets('Bozza maps to the neutral pair', (tester) async {
      final pair = await _pairFor(tester, 'Bozza');
      expect(pair.background, equals(p.bg3));
      expect(pair.foreground, equals(p.inkMuted));
    });

    testWidgets('Inviata maps to the tint "in flight" pair', (tester) async {
      final pair = await _pairFor(tester, 'Inviata');
      expect(pair.background, equals(infoBg));
      expect(pair.foreground, equals(v.tint));
    });

    testWidgets('In corso maps to statusWarn', (tester) async {
      final pair = await _pairFor(tester, 'In corso');
      expect(pair.background, equals(v.statusWarnBg));
      expect(pair.foreground, equals(v.statusWarn));
    });

    testWidgets('Completato maps to statusGood', (tester) async {
      final pair = await _pairFor(tester, 'Completato');
      expect(pair.background, equals(v.statusGoodBg));
      expect(pair.foreground, equals(v.statusGood));
    });

    testWidgets('Annullato maps to statusBad', (tester) async {
      final pair = await _pairFor(tester, 'Annullato');
      expect(pair.background, equals(v.statusBadBg));
      expect(pair.foreground, equals(v.statusBad));
    });

    testWidgets('Pagata maps to statusGood', (tester) async {
      final pair = await _pairFor(tester, 'Pagata');
      expect(pair.background, equals(v.statusGoodBg));
      expect(pair.foreground, equals(v.statusGood));
    });

    testWidgets('Scaduta maps to statusBad', (tester) async {
      final pair = await _pairFor(tester, 'Scaduta');
      expect(pair.background, equals(v.statusBadBg));
    });

    testWidgets('Sospeso maps to statusBad', (tester) async {
      final pair = await _pairFor(tester, 'Sospeso');
      expect(pair.background, equals(v.statusBadBg));
    });

    testWidgets('Attivo maps to statusGood', (tester) async {
      final pair = await _pairFor(tester, 'Attivo');
      expect(pair.background, equals(v.statusGoodBg));
    });

    testWidgets('an unknown status falls back to the neutral pair', (tester) async {
      final pair = await _pairFor(tester, 'Not A Real Status');
      expect(pair.background, equals(p.bg3));
      expect(pair.foreground, equals(p.inkMuted));
    });

    testWidgets('all 13 statuses return non-transparent colors', (tester) async {
      final statuses = [
        'Aperto',
        'In corso',
        'In pausa',
        'In attesa',
        'Completato',
        'Chiuso',
        'Annullato',
        'Bozza',
        'Inviata',
        'Pagata',
        'Scaduta',
        'Sospeso',
        'Attivo',
      ];
      for (final s in statuses) {
        final pair = await _pairFor(tester, s);
        expect(
          (pair.background.a * 255.0).round(),
          greaterThan(0),
          reason: 'background for $s should be opaque',
        );
        expect(
          (pair.foreground.a * 255.0).round(),
          greaterThan(0),
          reason: 'foreground for $s should be opaque',
        );
      }
    });
  });

  group('statusColorFromStato (legacy enum API)', () {
    testWidgets('bozza maps to the neutral pair', (tester) async {
      final pair = await _pairForStato(tester, ReportStato.bozza);
      expect(pair.background, equals(p.bg3));
      expect(pair.foreground, equals(p.inkMuted));
    });

    testWidgets('inviato maps to the tint "in flight" pair', (tester) async {
      final pair = await _pairForStato(tester, ReportStato.inviato);
      expect(pair.background, equals(infoBg));
      expect(pair.foreground, equals(v.tint));
    });

    testWidgets('controllato maps to statusWarn', (tester) async {
      final pair = await _pairForStato(tester, ReportStato.controllato);
      expect(pair.background, equals(v.statusWarnBg));
      expect(pair.foreground, equals(v.statusWarn));
    });

    testWidgets('fatturato maps to statusGood', (tester) async {
      final pair = await _pairForStato(tester, ReportStato.fatturato);
      expect(pair.background, equals(v.statusGoodBg));
      expect(pair.foreground, equals(v.statusGood));
    });

    testWidgets('annullato maps to statusBad', (tester) async {
      final pair = await _pairForStato(tester, ReportStato.annullato);
      expect(pair.background, equals(v.statusBadBg));
      expect(pair.foreground, equals(v.statusBad));
    });

    testWidgets('all statuses return non-transparent colors', (tester) async {
      for (final stato in ReportStato.values) {
        final pair = await _pairForStato(tester, stato);
        expect(
          (pair.background.a * 255.0).round(),
          greaterThan(0),
          reason: 'background for $stato should be opaque',
        );
        expect(
          (pair.foreground.a * 255.0).round(),
          greaterThan(0),
          reason: 'foreground for $stato should be opaque',
        );
      }
    });

    test('statoLabel returns Italian string for each stato', () {
      expect(statoLabel(ReportStato.bozza), 'Bozza');
      expect(statoLabel(ReportStato.inviato), 'Inviata');
      expect(statoLabel(ReportStato.controllato), 'Controllato');
      expect(statoLabel(ReportStato.fatturato), 'Pagata');
      expect(statoLabel(ReportStato.annullato), 'Annullato');
    });
  });

  group('AppColors', () {
    test('brand accent Y is stamp red #C03221', () {
      expect(AppColors.Y, equals(const Color(0xFFC03221)));
    });

    test('brand alias equals Y', () {
      expect(AppColors.brand, equals(AppColors.Y));
    });

    test('DARK has sufficient contrast (near-black)', () {
      expect(AppColors.DARK.computeLuminance(), lessThan(0.10));
    });

    test('onBrand alias equals DARK', () {
      expect(AppColors.onBrand, equals(AppColors.DARK));
    });

    test('AMBER is rgb(255,178,0)', () {
      expect(AppColors.AMBER, equals(const Color(0xFFFFB200)));
    });

    test('GREEN is #4caf50', () {
      expect(AppColors.GREEN, equals(const Color(0xFF4CAF50)));
    });

    test('BLUE is #2563eb', () {
      expect(AppColors.BLUE, equals(const Color(0xFF2563EB)));
    });

    test('CYAN is #06AED5', () {
      expect(AppColors.CYAN, equals(const Color(0xFF06AED5)));
    });

    test('BG1 is rgb(241,238,231) — the desk', () {
      expect(AppColors.BG1, equals(const Color(0xFFF1EEE7)));
    });

    test('DIV is rgb(222,217,206) — the one hairline', () {
      expect(AppColors.DIV, equals(const Color(0xFFDED9CE)));
    });

    test('SH shadow list is non-empty', () {
      expect(AppColors.SH, isNotEmpty);
    });

    test('SH_INSET shadow list is non-empty', () {
      expect(AppColors.SH_INSET, isNotEmpty);
    });
  });
}
