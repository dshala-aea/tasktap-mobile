// dart format width=100
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The chat's own confirmations: the microphone opens, a message leaves, a reply lands, a refusal.
///
/// Deliberately the platform's vocabulary — `HapticFeedback` and `SystemSound` — and not a sound
/// package. A technician holds the phone in one gloved hand at arm's length, often with the ringer
/// off, so the confirmation that actually arrives is the one through the case; the click is the
/// extra for people without a vibrator. Both are system sounds and system haptics, so the handset's
/// own silent-mode, haptics and accessibility settings apply without this app re-implementing them.
///
/// Nothing on screen depends on any of it: every call is best effort and swallows a platform that
/// has no vibrator or no sound channel. A reply landing is a haptic and never a noise — an app that
/// beeps in the middle of a customer conversation is worse than one that says nothing.
abstract class ChatFeedback {
  /// The microphone opened: the recording is live.
  Future<void> micStarted();

  /// The recording was closed by a tap (not by an interruption).
  Future<void> micStopped();

  /// A message was handed to the network.
  Future<void> sent();

  /// An assistant reply arrived, while the screen is in front of the technician.
  Future<void> replyArrived();

  /// The draft became complete enough to review: worth knowing without looking at the strip.
  Future<void> readyForReview();

  /// A turn failed, or the microphone refused.
  Future<void> refused();
}

/// The real thing, on the platform's own channels.
class SystemChatFeedback implements ChatFeedback {
  const SystemChatFeedback();

  @override
  Future<void> micStarted() => _run(
    () async {
      await HapticFeedback.mediumImpact();
      await SystemSound.play(SystemSoundType.click);
    },
  );

  @override
  Future<void> micStopped() => _run(
    () async {
      await HapticFeedback.heavyImpact();
      await SystemSound.play(SystemSoundType.click);
    },
  );

  @override
  Future<void> sent() => _run(
    () async {
      await HapticFeedback.selectionClick();
      await SystemSound.play(SystemSoundType.click);
    },
  );

  @override
  Future<void> replyArrived() => _run(() => HapticFeedback.lightImpact());

  @override
  Future<void> readyForReview() => _run(() => HapticFeedback.mediumImpact());

  @override
  Future<void> refused() => _run(
    () async {
      await HapticFeedback.vibrate();
      await SystemSound.play(SystemSoundType.alert);
    },
  );

  /// A handset without a vibrator, a sound channel, or a plugin registered (widget tests) must not
  /// turn feedback into a thrown exception on the way to a real failure message.
  Future<void> _run(Future<void> Function() body) async {
    try {
      await body();
    } catch (_) {
      // Feedback is a courtesy, never a dependency.
    }
  }
}

final chatFeedbackProvider = Provider<ChatFeedback>((ref) => const SystemChatFeedback());
