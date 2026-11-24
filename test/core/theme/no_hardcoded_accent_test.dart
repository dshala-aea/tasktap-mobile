import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _accentPattern = RegExp(r'AppColors\.(Y|YDark|YSoft)\b');

/// Returns the 1-based line numbers of [source] that reference the hardcoded
/// brand accent (`AppColors.Y`, `AppColors.YDark`, `AppColors.YSoft`).
///
/// Lines whose trimmed text starts with `//` are ignored. Deliberately
/// simple: no tokenizer, so a match inside a string literal is flagged too.
List<int> findHardcodedAccent(String source) {
  final hits = <int>[];
  final lines = source.split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trim().startsWith('//')) continue;
    if (_accentPattern.hasMatch(lines[i])) hits.add(i + 1);
  }
  return hits;
}

void main() {
  test('no hardcoded accent colours outside lib/core/theme', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (path.contains('lib/core/theme/')) continue;
      for (final line in findHardcodedAccent(entity.readAsStringSync())) {
        offenders.add('$path:$line');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'Use the tenant accent (AccentScheme) instead of '
          'AppColors.Y/YDark/YSoft:\n${offenders.join('\n')}',
    );
  });

  test('scanner self-check on an in-memory sample', () {
    const sample = '''
final a = AppColors.Y;
// AppColors.Y in a comment
    // AppColors.YDark indented comment
final b = AppColors.YDarker;
final c = 'AppColors.YSoft';
final d = AppColors.YDark;
''';
    // Line 5 is a string literal: flagged on purpose (kept simple).
    expect(findHardcodedAccent(sample), [1, 5, 6]);
  });
}
