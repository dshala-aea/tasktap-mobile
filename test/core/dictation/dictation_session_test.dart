// dart format width=100
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/dictation/dictation_outcome.dart';
import 'package:tasktap_mobile/core/dictation/dictation_session.dart';

/// What a silent session means. This is the whole reason `DictationSession` is separate from the
/// service: the "why did nothing happen" decision is pure bookkeeping, so it can be pinned here
/// without a method channel, a singleton or a device.
void main() {
  group('a session that produced words needs no excuse', () {
    test('words, then a clean end, reads as transcribed', () {
      final session = DictationSession()..onTranscript('sostituita la pompa');
      expect(session.outcome, DictationOutcome.transcribed);
      expect(session.outcome.notice, isNull);
    });

    test('words followed by an error are still transcribed', () {
      // The technician got their text. An error afterwards is worth nothing to them.
      final session = DictationSession()
        ..onTranscript('sostituita la pompa')
        ..onError('error_no_match');
      expect(session.outcome, DictationOutcome.transcribed);
    });

    test('stopping after words is still transcribed, not "stopped by user"', () {
      final session = DictationSession()
        ..onTranscript('sostituita la pompa')
        ..onStoppedByUser();
      expect(session.outcome, DictationOutcome.transcribed);
    });

    test('whitespace-only transcript does not count as a word', () {
      final session = DictationSession()..onTranscript('   ');
      expect(session.outcome, isNot(DictationOutcome.transcribed));
    });
  });

  group('a silent session says why it was silent', () {
    test('nothing at all points at the missing language pack', () {
      final session = DictationSession();
      expect(session.outcome, DictationOutcome.heardNothing);
      final notice = session.outcome.notice;
      expect(notice, isNotNull);
      expect(notice!.message, contains('pacchetto vocale'));
    });

    test('a generic recognition error invites a retry', () {
      final session = DictationSession()..onError('error_no_match');
      expect(session.outcome, DictationOutcome.recognitionFailed);
      expect(session.outcome.notice!.message, contains('Riprova'));
    });

    test('a missing language is told apart from a generic failure', () {
      final session = DictationSession()..onError('error_language_not_supported');
      expect(session.outcome, DictationOutcome.languageUnavailable);
    });

    test('a user stop with no words is never worth a message', () {
      final session = DictationSession()..onStoppedByUser();
      expect(session.outcome, DictationOutcome.stoppedByUser);
      expect(session.outcome.notice, isNull);
    });
  });
}
