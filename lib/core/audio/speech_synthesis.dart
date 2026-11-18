// dart format width=100
import 'dart:typed_data';

/// One synthesised stretch of speech, as the gateway returns it (`POST /api/ai/speech`).
class SpeechClip {
  const SpeechClip(this.bytes, this.contentType);

  final Uint8List bytes;

  /// e.g. `audio/mpeg`. The player needs it to pick a decoder for the in-memory bytes.
  final String contentType;
}

/// Why a clip could not be produced. Decides whether the engine retries the cloud on the next
/// reply or backs off for a while.
enum SpeechSynthesisFailure {
  /// Server has the feature switched off or the user may not use it (503 / 403). Not worth asking
  /// again for a while.
  notAvailable,

  /// The company's credits are spent (429). Spoken replies are an extra, so no grace: back off.
  quotaExhausted,

  /// Network, timeout or a provider hiccup. The next reply may well work.
  transient,
}

class SpeechSynthesisException implements Exception {
  const SpeechSynthesisException(this.failure, [this.message = '']);

  final SpeechSynthesisFailure failure;
  final String message;

  @override
  String toString() => 'SpeechSynthesisException($failure) $message';
}

/// Text in, audio out. Implemented by the API client; faked in tests.
abstract interface class SpeechSynthesizer {
  Future<SpeechClip> synthesize(String text);
}
