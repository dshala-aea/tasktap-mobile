import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/time/business_time.dart';

void main() {
  test('default zone constant is Europe/Rome', () {
    expect(kDefaultBusinessZoneId, 'Europe/Rome');
  });

  test('resolveBusinessZoneId keeps a valid IANA id', () {
    expect(resolveBusinessZoneId('America/New_York'), 'America/New_York');
    expect(resolveBusinessZoneId('Europe/Rome'), 'Europe/Rome');
  });

  for (final bad in <String?>[
    null,
    '',
    '  ',
    'Mars/Olympus',
    'W. Europe Standard Time',
    'europe/rome',
  ]) {
    test('resolveBusinessZoneId falls back for ${bad == null ? 'null' : "'$bad'"}',
        () {
      expect(resolveBusinessZoneId(bad), 'Europe/Rome');
    });
  }

  test('ensureTimeZonesInitialized is idempotent', () {
    expect(ensureTimeZonesInitialized, returnsNormally);
    expect(ensureTimeZonesInitialized, returnsNormally);
  });
}
