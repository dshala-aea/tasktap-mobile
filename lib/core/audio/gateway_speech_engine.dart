// dart format width=100
// `StreamAudioSource` is flagged experimental by just_audio but is its documented way to play
// in-memory bytes; the API has been stable for years.
// ignore_for_file: experimental_member_use
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'speech_output.dart';
import 'speech_sentences.dart';
import 'speech_synthesis.dart';

/// Plays one clip and completes when it has finished (or been stopped).
abstract interface class ClipPlayer {
  Future<void> play(SpeechClip clip);
  Future<void> stop();
  Future<void> dispose();
}

/// Reads assistant replies aloud with the server's voice (`POST /api/ai/speech`), sentence by
/// sentence: the first sentence starts as soon as it is synthesised while the next one is already
/// being fetched.
///
/// ## Always degrades, never breaks
///
/// Text is always on screen. Whenever the gateway cannot deliver (switched off, credits spent,
/// offline, a provider error) the remainder of the reply is handed to [_fallback], the on-device
/// voice, so the technician still hears the answer. A "not available" or "credits spent" answer
/// also parks the gateway for [backoff], so a tenant without the feature does not pay a failing
/// request on every reply.
///
/// ## Interruption
///
/// [stop] (and a new [speak]) bump a generation counter; the running pipeline checks it between
/// every step and quietly ends. That is the hook barge-in will use when the operator starts
/// talking over the assistant.
class GatewaySpeechEngine implements SpeechEngine {
  GatewaySpeechEngine({
    required SpeechSynthesizer synthesizer,
    required ClipPlayer player,
    required SpeechEngine fallback,
    this.backoff = const Duration(minutes: 10),
    DateTime Function()? clock,
  }) : _synth = synthesizer,
       _player = player,
       _fallback = fallback,
       _now = clock ?? DateTime.now;

  final SpeechSynthesizer _synth;
  final ClipPlayer _player;
  final SpeechEngine _fallback;
  final Duration backoff;
  final DateTime Function() _now;

  int _generation = 0;
  DateTime? _parkedUntil;
  Future<void> _running = Future.value();

  /// Completes when the current reply has finished playing (or was cut). For tests.
  @visibleForTesting
  Future<void> get idle => _running;

  bool get _parked {
    final until = _parkedUntil;
    return until != null && _now().isBefore(until);
  }

  @override
  Future<void> speak(String text) async {
    final generation = ++_generation;
    await _stopPlayback();
    final sentences = splitSpeakable(text);
    if (sentences.isEmpty) return;
    if (_parked) {
      await _fallback.speak(text);
      return;
    }
    _running = _run(generation, sentences);
    unawaited(_running);
  }

  @override
  Future<void> stop() async {
    _generation++;
    await _stopPlayback();
  }

  Future<void> _stopPlayback() async {
    try {
      await _player.stop();
    } catch (e) {
      debugPrint('Speech player stop failed: $e');
    }
    await _fallback.stop();
  }

  bool _current(int generation) => generation == _generation;

  Future<void> _run(int generation, List<String> sentences) async {
    Future<SpeechClip> fetch(int i) => _synth.synthesize(sentences[i]);

    var next = fetch(0);
    for (var i = 0; i < sentences.length; i++) {
      if (!_current(generation)) return;
      final SpeechClip clip;
      try {
        clip = await next;
      } on SpeechSynthesisException catch (e) {
        if (!_current(generation)) return;
        if (e.failure != SpeechSynthesisFailure.transient) {
          _parkedUntil = _now().add(backoff);
        }
        await _speakRest(generation, sentences, i);
        return;
      } catch (e) {
        if (!_current(generation)) return;
        debugPrint('Speech synth failed: $e');
        await _speakRest(generation, sentences, i);
        return;
      }
      if (!_current(generation)) return;
      // Start the next sentence's synthesis before this one plays; swallow its error here, it is
      // handled when we get to it.
      if (i + 1 < sentences.length) {
        next = fetch(i + 1);
        unawaited(next.then<void>((_) {}, onError: (Object _) {}));
      }
      try {
        await _player.play(clip);
      } catch (e) {
        if (!_current(generation)) return;
        debugPrint('Speech playback failed: $e');
        await _speakRest(generation, sentences, i + 1);
        return;
      }
    }
  }

  Future<void> _speakRest(int generation, List<String> sentences, int from) async {
    if (from >= sentences.length || !_current(generation)) return;
    await _fallback.speak(sentences.sublist(from).join(' '));
  }
}

/// `just_audio` playing clips from memory.
class JustAudioClipPlayer implements ClipPlayer {
  JustAudioClipPlayer({AudioPlayer? player}) : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  Future<void> play(SpeechClip clip) async {
    await _player.setAudioSource(_BytesSource(clip.bytes, clip.contentType));
    // Completes when playback ends, is paused, or is stopped.
    await _player.play();
  }

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

class _BytesSource extends StreamAudioSource {
  _BytesSource(this._bytes, this._contentType);

  final Uint8List _bytes;
  final String _contentType;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final from = start ?? 0;
    final to = end ?? _bytes.length;
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: to - from,
      offset: from,
      stream: Stream.value(_bytes.sublist(from, to)),
      contentType: _contentType,
    );
  }
}
