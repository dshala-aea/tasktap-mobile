// dart format width=100
import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// Hard stop for one recording. The server rejects anything over 10 minutes
/// (`audio_too_long`), so the client stops well before and never produces an upload that is
/// refused for length.
const Duration maxRecordingLength = Duration(minutes: 5);

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
/// the header, and bills compressed audio from max(header duration, bytes / 24000)), mono, 16 kHz,
/// ~64 kbps. WAV is never used (billed by byte rate, ~6x larger).
class RecordAudioRecorderService implements AudioRecorderService {
  RecordAudioRecorderService({AudioRecorder? recorder}) : _recorder = recorder ?? AudioRecorder();

  static const RecordConfig config = RecordConfig(
    encoder: AudioEncoder.aacLc,
    bitRate: 64000,
    sampleRate: 16000,
    numChannels: 1,
  );

  final AudioRecorder _recorder;
  StreamController<Duration>? _elapsed;
  StreamSubscription<RecordState>? _stateSub;
  Timer? _ticker;
  final Stopwatch _clock = Stopwatch();
  bool _stopRequested = false;

  @override
  Stream<Duration> get elapsed => (_elapsed ??= StreamController<Duration>.broadcast()).stream;

  @override
  Future<void> start() async {
    final dir = await getTemporaryDirectory();
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
    _clock.stop();
    _ticker?.cancel();
    await _stateSub?.cancel();
    final path = await _recorder.stop();
    _endStream();
    if (path == null) throw StateError('Nessuna registrazione in corso.');
    return File(path);
  }

  void _endStream() {
    _ticker?.cancel();
    final c = _elapsed;
    _elapsed = null;
    if (c != null && !c.isClosed) c.close();
  }

  Future<void> dispose() => _recorder.dispose();
}
