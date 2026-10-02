import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Business dates are Europe/Rome calendar days, never the phone's. Building a midnight from a
/// local `DateTime(x.year, x.month, x.day)` (or splicing a clock string onto a date) silently
/// uses the device zone, so these constructs must not reappear in the timbratura code.
void main() {
  // Explicit and empty: no file is exempt.
  const allowList = <String>[];

  final deviceMidnight = RegExp(r'DateTime\(\s*\w+\.year,\s*\w+\.month,\s*\w+\.day');
  const banned = ['_combineWorkDateAnd', '_hms('];

  group('guard matcher', () {
    test('matches a device-zone midnight', () {
      expect(deviceMidnight.hasMatch('DateTime(now.year, now.month, now.day)'), isTrue);
      expect(deviceMidnight.hasMatch('DateTime( d.year,\n d.month,\n d.day)'), isTrue);
    });

    test('does not match a UTC construction', () {
      expect(deviceMidnight.hasMatch('DateTime.utc(d.year, d.month, d.day)'), isFalse);
    });
  });

  group('source scan', () {
    List<File> dartFiles(String dir) => Directory(dir)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !allowList.any(f.path.endsWith))
        .toList();

    final files = [
      ...dartFiles('lib/data/timbratura'),
      ...dartFiles('lib/features/timbra'),
    ];

    test('the scan sees files', () {
      expect(files, isNotEmpty);
    });

    test('no device-zone midnight or clock splicing in timbratura code', () {
      final offenders = <String>[];
      for (final f in files) {
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final l = lines[i];
          if (deviceMidnight.hasMatch(l) || banned.any(l.contains)) {
            offenders.add('${f.path}:${i + 1}: ${l.trim()}');
          }
        }
        // Multi-line constructor form.
        if (deviceMidnight.hasMatch(f.readAsStringSync()) &&
            !offenders.any((o) => o.startsWith(f.path))) {
          offenders.add('${f.path}: multi-line device-zone midnight');
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test('business_time.dart never reads the device zone', () {
      final src = File('lib/core/time/business_time.dart').readAsStringSync();
      expect(src.contains('DateTime.now().timeZone'), isFalse);
    });
  });
}
