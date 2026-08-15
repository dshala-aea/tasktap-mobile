import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

/// Italian dates need their locale data loaded before anything formats one.
///
/// intl ships no locale data until it is asked for some. Every screen in this app builds dates
/// with `DateFormat(..., 'it')`, and startup never called `initializeDateFormatting`, so the first
/// such widget threw
///
///     LocaleDataException: Locale data has not been initialized,
///     call initializeDateFormatting(<locale>).
///
/// during build — which does not produce a wrong date, it produces an error box where the screen
/// was. On the device this cascaded: a broken subtree inside a scrolling column reported an
/// overflow of ninety-nine thousand pixels.
void main() {
  group('date formatting', () {
    test('the app initialises the locale it formats in', () {
      final main = File('lib/main.dart').readAsStringSync();

      expect(
        main.contains('initializeDateFormatting('),
        isTrue,
        reason: 'startup must load intl locale data before any DateFormat(..., "it") runs',
      );
      expect(
        main.contains("Intl.defaultLocale = 'it'"),
        isTrue,
        reason:
            'the DateFormat calls that pass no locale should format like the ones that do, '
            'rather than falling back to en_US',
      );
    });

    /// The patterns the app actually uses. `d MMMM` and `EEEE` are the ones that need symbol
    /// data — a numeric-only pattern would pass even with nothing loaded, and prove nothing.
    test('Italian month and day names format once initialised', () async {
      await initializeDateFormatting('it', null);

      final date = DateTime(2026, 8, 14);

      expect(DateFormat('EEEE', 'it').format(date).toLowerCase(), 'venerdì');
      expect(DateFormat('MMMM', 'it').format(date).toLowerCase(), 'agosto');
      expect(DateFormat('dd/MM/yyyy', 'it').format(date), '14/08/2026');
    });

    test('a locale-less DateFormat follows Intl.defaultLocale', () async {
      await initializeDateFormatting('it', null);
      Intl.defaultLocale = 'it';
      addTearDown(() => Intl.defaultLocale = null);

      expect(DateFormat('MMMM').format(DateTime(2026, 8, 14)).toLowerCase(), 'agosto');
    });
  });
}
