// dart format width=100
// test/core/audio/record_audio_recorder_service_test.dart
//
// The iOS dead microphone. `record_ios` discards the `Bool` from `AVAudioRecorder.record()` and
// reports `RecordState.record` regardless, so a session that refused to start — a call, another
// app holding the input, an activation that lost a race — is indistinguishable from a good one.
// Before this, the app only found out when the technician tapped stop, having spoken a whole
// description into nothing while the counter ran.
//
// These tests drive the liveness probe through a fake platform recorder, so the rule that decides
// "dead" is exercised without a device: no bytes on disk AND the input on its floor.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:tasktap_mobile/core/audio/audio_recorder_service.dart';
import 'package:tasktap_mobile/core/crash_reporting/crash_reporter.dart';

/// A container header: what `AVAudioRecorder.prepareToRecord()` leaves before any audio arrives.
const int _headerBytes = 300;

/// Stands in for `AudioRecorder`. Only the members this service touches are implemented; the rest
/// are unreachable from here and answered by [noSuchMethod].
class _FakePlatformRecorder implements AudioRecorder {
  _FakePlatformRecorder({
    required this.amplitude,
    this.flushedBytes = _headerBytes,
    this.totalBytes = _headerBytes,
    this.iosSession,
  });

  /// What `getAmplitude` answers — the floor (-160.0) reads as "nothing is coming in".
  final double amplitude;

  /// What is already in the file when the probe looks: a live recorder streams there continuously,
  /// a platform is free to hold it until stop.
  final int flushedBytes;

  /// What the file holds once the recorder is stopped.
  final int totalBytes;

  /// Set to give the service an iOS session to release; null models any other platform.
  final _FakeRecordIos? iosSession;

  String? _path;
  int starts = 0;
  int stops = 0;
  bool disposed = false;
  Object? amplitudeError;
  RecordConfig? lastConfig;

  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    starts++;
    lastConfig = config;
    _path = path;
    await File(path).writeAsBytes(List<int>.filled(flushedBytes, 0), flush: true);
  }

  @override
  Future<String?> stop() async {
    stops++;
    final path = _path;
    _path = null;
    if (path == null) return null;
    await File(path).writeAsBytes(List<int>.filled(totalBytes, 0), flush: true);
    return path;
  }

  @override
  Future<Amplitude> getAmplitude() async {
    final error = amplitudeError;
    if (error != null) throw error;
    return Amplitude(current: amplitude, max: amplitude);
  }

  @override
  Stream<RecordState> onStateChanged() => const Stream<RecordState>.empty();

  @override
  RecordIos? get ios => iosSession;

  @override
  Future<void> dispose() async => disposed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeRecordIos implements RecordIos {
  final sessionCalls = <bool>[];

  @override
  Future<void> setAudioSessionActive(bool active) async => sessionCalls.add(active);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _RecordingCrashReporter implements CrashReporter {
  final exceptions = <Object>[];
  final breadcrumbs = <String>[];

  @override
  Future<void> captureException(Object exception, {StackTrace? stackTrace, String? hint}) async =>
      exceptions.add(exception);

  @override
  Future<void> captureMessage(String message) async {}

  @override
  void addBreadcrumb(String message, {String? category}) => breadcrumbs.add(message);
}

void main() {
  late Directory tmp;
  late _FakePlatformRecorder platform;
  late _RecordingCrashReporter reporter;
  late CrashReporter previousReporter;

  RecordAudioRecorderService service({
    double amplitude = -160.0,
    int flushedBytes = _headerBytes,
    int totalBytes = _headerBytes,
    Object? amplitudeError,
    _FakeRecordIos? iosSession,
    Duration probeDelay = const Duration(milliseconds: 30),
  }) {
    platform = _FakePlatformRecorder(
      amplitude: amplitude,
      flushedBytes: flushedBytes,
      totalBytes: totalBytes,
      iosSession: iosSession,
    )..amplitudeError = amplitudeError;
    return RecordAudioRecorderService(
      recorder: platform,
      probeDelay: probeDelay,
      tempDirectory: () async => tmp,
    );
  }

  /// Completes when the service ends the take by itself (the elapsed stream closes).
  Future<void> endedOnItsOwn(RecordAudioRecorderService s) {
    final done = Completer<void>();
    final sub = s.elapsed.listen((_) {}, onDone: done.complete);
    return done.future
        .timeout(const Duration(seconds: 2))
        .whenComplete(() => unawaited(sub.cancel()));
  }

  Future<bool> endsWithin(RecordAudioRecorderService s, Duration window) async {
    var ended = false;
    final sub = s.elapsed.listen((_) {}, onDone: () => ended = true);
    await Future<void>.delayed(window);
    await sub.cancel();
    return ended;
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('voice_probe');
    reporter = _RecordingCrashReporter();
    previousReporter = CrashReporter.instance;
    CrashReporter.setInstance(reporter);
  });

  tearDown(() async {
    CrashReporter.setInstance(previousReporter);
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test('A recorder that never captured ends the take instead of waiting for the tap', () async {
    final s = service();

    await s.start();
    await endedOnItsOwn(s);

    expect(reporter.breadcrumbs.single, contains('voice: no input after'));
    expect(reporter.breadcrumbs.single, contains('$_headerBytes byte'));
    expect(platform.stops, 0, reason: 'the owner stops the recorder, exactly once');

    // What the owner does next: the take is flushed, weighed and found empty.
    final file = await s.stop();
    expect(await file.length(), lessThan(minCapturedBytes));
    expect(platform.stops, 1);
  });

  test('A quiet room with a live microphone is left alone', () async {
    // Bytes still in the platform's buffer (a late flush), but the input is hearing the room: the
    // take must survive. This is the case that makes the probe require BOTH signals.
    final s = service(amplitude: -45.0, totalBytes: 24000);

    await s.start();
    expect(await endsWithin(s, const Duration(milliseconds: 200)), isFalse);
    expect(platform.stops, 0);

    final file = await s.stop();
    expect(await file.length(), greaterThanOrEqualTo(minCapturedBytes));
  });

  test('Audio on disk is proof enough even when the level sits on the floor', () async {
    // Silence at the very bottom of the scale still writes bytes: "no bytes" is what "not
    // recording" means, so a take that is already writing is never cut.
    final s = service(amplitude: -160.0, flushedBytes: 5000, totalBytes: 24000);

    await s.start();
    expect(await endsWithin(s, const Duration(milliseconds: 200)), isFalse);
    await s.stop();
  });

  test('An unavailable amplitude falls back to the check at stop', () async {
    final s = service(amplitudeError: UnsupportedError('no amplitude'));

    await s.start();
    expect(
      await endsWithin(s, const Duration(milliseconds: 200)),
      isFalse,
      reason: 'no measurement is not evidence of a dead microphone',
    );
    await s.stop();
  });

  test('Stopping releases the audio session and the probe does not fire afterwards', () async {
    final ios = _FakeRecordIos();
    final s = service(iosSession: ios, probeDelay: const Duration(milliseconds: 120));

    await s.start();
    await s.stop();
    await Future<void>.delayed(const Duration(milliseconds: 250));

    expect(ios.sessionCalls, [false], reason: 'record_ios leaves the session active unless asked');
    expect(platform.stops, 1, reason: 'the cancelled probe never stops the recorder again');
    expect(reporter.breadcrumbs, isEmpty);
  });

  test('The recorder is started with the rates AVAudioRecorder accepts', () async {
    // `record` and its maintainer advise leaving bit rate and sample rate at their defaults: the
    // plugin only adjusts custom values as a best effort, and on iOS an unsupported combination
    // makes AVAudioRecorder.record() return false. record_ios throws that Bool away and reports a
    // healthy state, so the take is silently empty — the "microfono non ha registrato nulla" the
    // technician sees. 16 kHz / 64 kbps mono was exactly such a custom combination.
    final s = service(flushedBytes: 5000, totalBytes: 24000);

    await s.start();
    await s.stop();

    final config = platform.lastConfig!;
    expect(config.encoder, AudioEncoder.aacLc, reason: 'the server stores m4a/AAC');
    expect(config.sampleRate, 44100, reason: 'the platform default, not a custom 16 kHz request');
    expect(config.bitRate, 128000, reason: 'the platform default, not a custom 64 kbps request');
    expect(config.numChannels, 1, reason: 'speech is mono; stereo files double nothing useful');
  });

  test('The recorder is disposed once', () async {
    final s = service(probeDelay: const Duration(seconds: 5));
    await s.start();
    await s.stop();
    await s.dispose();
    expect(platform.disposed, isTrue);
  });
}
