import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keeps the press-feedback split principled instead of leftover.
///
/// Before this pass the app used [GestureDetector] nineteen times and `InkWell` eight, and the
/// choice was not a decision anyone had made — controls a technician taps all day happened to have
/// the silent one. Converting them fixes today; this stops tomorrow's new screen from adding a
/// twentieth by habit, which is exactly how the split got that way the first time.
///
/// A file is allowed here only with a reason written at the call site. If a new one belongs on the
/// list, add it *and* the comment — the entry alone is a suppression, not a decision.
void main() {
  /// Every place a bare `GestureDetector(` may still be constructed, and why.
  const allowed = <String, String>{
    'lib/core/widgets/app_toggle.dart':
        'the thumb animates on tap — the movement is the feedback',
    'lib/core/widgets/signature_pad.dart':
        'a drag, not a press; there is nothing to splash',
    'lib/core/widgets/bottom_nav.dart':
        'the pill animates colour, padding and label on every selection',
    'lib/features/calendario/calendario_screen.dart':
        'the day disc is an AnimatedContainer that moves on selection',
    'lib/features/timbra/timbra_screen.dart':
        'the 180dp gradient disc: ink over a glow reads as a smudge, and it swaps to a spinner',
  };

  test('only the documented exceptions use a bare GestureDetector', () {
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final path = entity.path.replaceAll(r'\', '/');
      // Constructor calls only. The doc comments that name GestureDetector to explain why
      // something is not one would otherwise report themselves.
      if (!entity.readAsStringSync().contains('GestureDetector(')) continue;
      if (allowed.containsKey(path)) continue;

      offenders.add(path);
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Use AppTappable so the control answers a press. If this one genuinely should not '
          '(it animates on tap, or the gesture is a drag), add it to `allowed` above with the '
          'reason, and write that reason at the call site too.',
    );
  });

  /// An allowlist that outlives the file it names is how a rule quietly stops applying.
  test('every allowed file still exists and still has one', () {
    for (final entry in allowed.entries) {
      final file = File(entry.key);
      expect(file.existsSync(), isTrue, reason: '${entry.key} is on the allowlist but is gone');
      expect(
        file.readAsStringSync().contains('GestureDetector('),
        isTrue,
        reason: '${entry.key} no longer uses GestureDetector — drop it from the allowlist',
      );
    }
  });
}
