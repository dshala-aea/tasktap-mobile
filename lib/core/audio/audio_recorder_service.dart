// dart format width=100
import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../crash_reporting/crash_reporter.dart';

/// Hard stop for one recording. The server rejects anything over 10 minutes
/// (`audio_too_long`), so the client stops well before and never produces an upload that is
/// refused for length.
const Duration maxRecordingLength = Duration(minutes: 5);

/// The smallest file that can hold audio at all. A recording that captured nothing is a container
/// header and little else — under a kilobyte — and uploading it only earns the server's
/// `audio_too_short`, which reads as "you spoke too briefly" when in fact the microphone never
/// recorded.
///
/// On iOS that is a live possibility, not a theory: `record_ios` ignores the `Bool` returned by
/// `AVAudioRecorder.record()` and reports `RecordState.record` regardless, so a session that
/// refused to start (microphone held by a call or another recorder, activation failure) looks
/// exactly like a healthy one until the file is weighed. 2 KiB is a quarter second at the
/// 64 kbit/s this path records — far below any deliberate utterance, far above a bare header.
const int minCapturedBytes = 2048;

/// How long a take is left alone before the microphone is checked for a pulse. Below a second the
/// answer means nothing (the technician has barely started), and by three seconds a working recorder
/// has written ~20 kB at this bitrate, so "no bytes at all" is already conclusive.
const Duration captureProbeDelay = Duration(seconds: 3);

/// The dBFS both platforms report when the recorder is hearing nothing whatsoever. A live
/// microphone in a quiet room does not sit exactly on the floor — room noise holds it above it — so
/// the floor is the one level that means "no input" rather than "silence".
const double silentAmplitudeFloor = -159.9;

/// Records one voice update to a local file. This is the ONLINE path (upload to
/// `POST /api/ai/voice-captures`, which stores the audio without transcribing it); on-device
/// dictation lives in `lib/core/dictation/` and is separate.
///
/// Permission and consent are NOT this class's concern: see `VoiceCaptureController`.
abstract class AudioRecorderService {
  /// Begins recording. Throws if the platform recorder cannot start.
  Future<void> start();

  /// Ends the recording and returns the file recorded so far. Safe after an interruption.
  Future<File> stop();

  /// Time recorded so far. The stream CLOSES if the recording ended without [stop] being called
  /// (another app or a phone call took the microphone), which callers treat as an interruption.
  Stream<Duration> get elapsed;
}

/// The outcome of asking for the microphone — reported, never thrown.
enum MicPermission { granted, denied, permanentlyDenied }

abstract class MicPermissionService {
  Future<MicPermission> request();
}

class PermissionHandlerMicPermissionService implements MicPermissionService {
  const PermissionHandlerMicPermissionService();

  @override
  Future<MicPermission> request() async {
    final status = await Permission.microphone.request();
    if (status.isGranted) return MicPermission.granted;
    if (status.isPermanentlyDenied || status.isRestricted) return MicPermission.permanentlyDenied;
    return MicPermission.denied;
  }
}

/// Production recorder on the `record` package.
///
/// Output must be m4a: AAC in a non-fragmented MP4 container (the server reads the duration from
/// the header, and bills compressed audio from max(header duration, bytes / 24000)), mono.
///
/// Bit rate and sample rate are deliberately left at the package defaults, not narrowed to a
/// speech-sized 16 kHz / 64 kbps. `record` only adjusts custom values to the codec's capabilities
/// as a best effort, and on iOS `AVAudioRecorder.record()` answers `false` for a combination it
/// cannot honour — which `record_ios` discards, reporting a healthy take that is in fact empty.
/// The defaults (44.1 kHz / 128 kbps) are the combination Apple's AAC encoder is built around; the
/// 5-minute cap keeps the file at ~4.8 MB, well under the server's 25 MB limit, and the container
/// duration the server reads is exact, so the higher rate costs no extra billed seconds.
class RecordAudioRecorderService implements AudioRecorderService {
  RecordAudioRecorderService({
    AudioRecorder? recorder,
    this.probeDelay = captureProbeDelay,
    Future<Directory> Function()? tempDirectory,
  }) : _recorder = recorder ?? AudioRecorder(),
       _tempDirectory = tempDirectory ?? getTemporaryDirectory;

  /// How long after [start] the microphone is checked for a pulse. Injectable so tests do not wait
  /// the real three seconds.
  final Duration probeDelay;

  /// Where takes are written. Injectable so tests do not need the platform channel.
  final Future<Directory> Function() _tempDirectory;

  static const RecordConfig config = RecordConfig(encoder: AudioEncoder.aacLc, numChannels: 1);

  final AudioRecorder _recorder;
  StreamController<Duration>? _elapsed;
  StreamSubscription<RecordState>? _stateSub;
  Timer? _ticker;
  Timer? _probe;
  final Stopwatch _clock = Stopwatch();
  bool _stopRequested = false;

  @override
  Stream<Duration> get elapsed => (_elapsed ??= StreamController<Duration>.broadcast()).stream;

  @override
  Future<void> start() async {
    final dir = await _tempDirectory();
    // The app's own container, so no iOS permission stands in the way — but a purged or full
    // sandbox is not impossible, and it must fail here, loudly, rather than as a silent empty take.
    await dir.create(recursive: true);
    final path = '${dir.path}/voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
    _elapsed ??= StreamController<Duration>.broadcast();
    _stopRequested = false;
    await _recorder.start(config, path: path);
    _clock
      ..reset()
      ..start();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      _elapsed?.add(_clock.elapsed);
    });
    _probe = Timer(probeDelay, () => unawaited(_probeLiveness(path)));
    // The plugin pauses (default audioInterruption) when a call or another app takes the mic.
    // A paused or stopped recorder that we did not ask to stop is an interruption: end the
    // stream so the owner finalises the file recorded so far instead of waiting on silence.
    _stateSub = _recorder.onStateChanged().listen((s) {
      if (!_stopRequested && s != RecordState.record) _endStream();
    });
  }

  @override
  Future<File> stop() async {
    _stopRequested = true;
    _probe?.cancel();
    _clock.stop();
    _ticker?.cancel();
    await _stateSub?.cancel();
    _stateSub = null;
    final path = await _recorder.stop();
    await _releaseAudioSession();
    _endStream();
    if (path == null) throw StateError('Nessuna registrazione in corso.');
    return File(path);
  }

  /// Checks, a few seconds in, that the microphone is actually capturing — and ends the take at once
  /// when it is not.
  ///
  /// `record_ios` throws away the `Bool` from `AVAudioRecorder.record()` and reports a healthy state
  /// regardless, so a session that refused to start (a call, another app holding the input, an
  /// activation that lost a race) looks exactly like a good one. Until now the only way to find out
  /// was to weigh the file when the technician tapped stop — i.e. after they had said a whole
  /// paragraph into a microphone that was never on, and with a counter running that said otherwise.
  ///
  /// Two independent signals are required before a take is called dead, because either one alone
  /// lies: a quiet room reads the floor, and a platform is free to flush the file late.
  /// No bytes yet AND the input reading its floor is a recorder that is not recording.
  Future<void> _probeLiveness(String path) async {
    if (_stopRequested) return;
    final int bytes;
    try {
      bytes = await File(path).length();
    } catch (_) {
      return; // Nothing to weigh: no conclusion.
    }
    if (bytes >= minCapturedBytes) return; // It is writing audio: leave the take alone.
    final double level;
    try {
      level = (await _recorder.getAmplitude()).current;
    } catch (_) {
      return; // No amplitude on this platform: fall back to the check at stop.
    }
    if (level > silentAmplitudeFloor) return; // It hears something: leave the take alone.
    _endSilentTake(bytes, level);
  }

  /// Ends a take the microphone never captured, so the owner finishes the recording now instead of
  /// when the technician gives up on it.
  ///
  /// The recorder itself is stopped by the owner's [stop] — the very same call that closes a normal
  /// take — so the file is flushed and weighed exactly once, by the code that already knows what an
  /// empty one means (`EmptyRecordingException`).
  void _endSilentTake(int bytes, double level) {
    _stopRequested = true;
    CrashReporter.instance.addBreadcrumb(
      'voice: no input after ${probeDelay.inMilliseconds}ms '
      '($bytes byte, ${level.toStringAsFixed(1)} dBFS)',
      category: 'voice',
    );
    _endStream();
  }

  /// Gives the audio session back. `record_ios` only deactivates it when asked, so leaving it active
  /// keeps the OS microphone indicator on and holds the input route — one of the ways the next take
  /// can be refused an input. Best effort: a session that was already interrupted throws here.
  Future<void> _releaseAudioSession() async {
    try {
      await _recorder.ios?.setAudioSessionActive(false);
    } catch (_) {
      // Not the failure this method exists for.
    }
  }

  void _endStream() {
    _probe?.cancel();
    _ticker?.cancel();
    final c = _elapsed;
    _elapsed = null;
    if (c != null && !c.isClosed) c.close();
  }

  Future<void> dispose() {
    _probe?.cancel();
    return _recorder.dispose();
  }
}
