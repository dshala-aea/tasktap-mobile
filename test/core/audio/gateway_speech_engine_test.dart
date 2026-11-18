// dart format width=100
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/audio/gateway_speech_engine.dart';
import 'package:tasktap_mobile/core/audio/speech_output.dart';
import 'package:tasktap_mobile/core/audio/speech_sentences.dart';
import 'package:tasktap_mobile/core/audio/speech_synthesis.dart';

class _Synth implements SpeechSynthesizer {
  final requests = <String>[];
  final Map<String, SpeechSynthesisFailure> failures = {};
  Completer<void>? gate;

  @override
  Future<SpeechClip> synthesize(String text) async {
    requests.add(text);
    final g = gate;
    if (g != null) await g.future;
    final f = failures[text];
    if (f != null) throw SpeechSynthesisException(f);
    return SpeechClip(Uint8List.fromList(text.codeUnits), 'audio/mpeg');
  }
}

class _Player implements ClipPlayer {
  final played = <String>[];
  /// When true, the next `play` blocks until `stop` (a clip that is "still playing").
  bool holdNextPlay = false;
  Completer<void>? _hold;
  bool stopped = false;

  @override
  Future<void> play(SpeechClip clip) async {
    played.add(String.fromCharCodes(clip.bytes));
    if (holdNextPlay) {
      holdNextPlay = false;
      final h = _hold = Completer<void>();
      await h.future;
    }
  }

  @override
  Future<void> stop() async {
    stopped = true;
    final h = _hold;
    if (h != null && !h.isCompleted) h.complete();
  }

  @override
  Future<void> dispose() async {}
}

class _Fallback implements SpeechEngine {
  final spoken = <String>[];
  int stops = 0;

  @override
  Future<void> speak(String text) async => spoken.add(text);

  @override
  Future<void> stop() async => stops++;
}

const _long1 = 'Ho controllato il rapportino e manca la descrizione del guasto trovato.';
const _long2 = 'Vuoi che aggiunga che il quadro era fermo per un contatto ossidato?';

void main() {
  late _Synth synth;
  late _Player player;
  late _Fallback fallback;
  var now = DateTime(2026, 11, 18, 10);

  GatewaySpeechEngine build() => GatewaySpeechEngine(
    synthesizer: synth,
    player: player,
    fallback: fallback,
    clock: () => now,
  );

  setUp(() {
    synth = _Synth();
    player = _Player();
    fallback = _Fallback();
    now = DateTime(2026, 11, 18, 10);
  });

  group('splitSpeakable', () {
    test('splits on sentence ends and keeps the punctuation', () {
      expect(splitSpeakable('$_long1 $_long2'), [_long1, _long2]);
    });

    test('merges short fragments into the next sentence', () {
      final parts = splitSpeakable('Ok. $_long1');
      expect(parts, ['Ok. $_long1']);
    });

    test('drops markdown decoration and blank input', () {
      expect(splitSpeakable('**Attenzione** il quadro è fermo da due giorni per un guasto.'), [
        'Attenzione il quadro è fermo da due giorni per un guasto.',
      ]);
      expect(splitSpeakable('  \n '), isEmpty);
    });

    test('cuts an over-long run without punctuation', () {
      final text = List.filled(80, 'parola').join(' ');
      final parts = splitSpeakable(text);
      expect(parts.length, greaterThan(1));
      expect(parts.every((p) => p.length <= 240), isTrue);
    });
  });

  group('GatewaySpeechEngine', () {
    test('plays each sentence in order from the gateway', () async {
      final engine = build();
      await engine.speak('$_long1 $_long2');
      await engine.idle;
      expect(player.played, [_long1, _long2]);
      expect(fallback.spoken, isEmpty);
    });

    test('hands the reply to the phone voice when the gateway is not available', () async {
      synth.failures[_long1] = SpeechSynthesisFailure.notAvailable;
      final engine = build();
      await engine.speak('$_long1 $_long2');
      await engine.idle;
      expect(player.played, isEmpty);
      expect(fallback.spoken, ['$_long1 $_long2']);
    });

    test('backs off after not-available, then retries once the pause is over', () async {
      synth.failures[_long1] = SpeechSynthesisFailure.notAvailable;
      final engine = build();
      await engine.speak(_long1);
      await engine.idle;
      synth.requests.clear();

      await engine.speak(_long1);
      await engine.idle;
      expect(synth.requests, isEmpty, reason: 'parked: no request while backing off');
      expect(fallback.spoken.length, 2);

      now = now.add(const Duration(minutes: 11));
      synth.failures.clear();
      await engine.speak(_long1);
      await engine.idle;
      expect(player.played, [_long1]);
    });

    test('a transient failure falls back for this reply only', () async {
      synth.failures[_long1] = SpeechSynthesisFailure.transient;
      final engine = build();
      await engine.speak(_long1);
      await engine.idle;
      expect(fallback.spoken, [_long1]);

      synth.failures.clear();
      await engine.speak(_long1);
      await engine.idle;
      expect(player.played, [_long1]);
    });

    test('a failure mid-reply speaks only the sentences not yet played', () async {
      synth.failures[_long2] = SpeechSynthesisFailure.transient;
      final engine = build();
      await engine.speak('$_long1 $_long2');
      await engine.idle;
      expect(player.played, [_long1]);
      expect(fallback.spoken, [_long2]);
    });

    test('stop cuts the reply: nothing more is played or spoken', () async {
      player.holdNextPlay = true;
      final engine = build();
      await engine.speak('$_long1 $_long2');
      await Future<void>.delayed(Duration.zero);
      await engine.stop();
      await engine.idle;
      expect(player.played, [_long1]);
      expect(fallback.spoken, isEmpty);
    });

    test('a new reply replaces the one still playing', () async {
      player.holdNextPlay = true;
      final engine = build();
      await engine.speak('$_long1 $_long2');
      await Future<void>.delayed(Duration.zero);
      await engine.speak(_long2);
      await engine.idle;
      expect(player.played, [_long1, _long2]);
    });

    test('blank text does nothing', () async {
      final engine = build();
      await engine.speak('   ');
      await engine.idle;
      expect(synth.requests, isEmpty);
    });
  });
}
