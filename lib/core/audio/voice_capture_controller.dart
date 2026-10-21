// dart format width=100
import 'dart:async';
import 'dart:io';

import '../../data/ai/ai_api_client.dart';
import 'audio_recorder_service.dart';
import 'pending_recording_store.dart';

enum RecordingStartResult { started, consentRequired, permissionDenied, permissionPermanentlyDenied }

/// Orchestrates one voice update: consent, then microphone permission, then record, persist,
/// upload. Every refusal is a returned [RecordingStartResult], never an exception.
class VoiceCaptureController {
  VoiceCaptureController({
    required this.recorder,
    required this.permissions,
    required this.store,
    required this.consentAccepted,
    required Future<AiTranscription> Function(File audio, String idempotencyKey) upload,
  }) : _uploader = upload;

  final AudioRecorderService recorder;
  final MicPermissionService permissions;
  final PendingRecordingStore store;
  final Future<bool> Function() consentAccepted;
  final Future<AiTranscription> Function(File audio, String idempotencyKey) _uploader;

  bool get isRecording => _recording;

  /// Emits the saved recording when it ended without [stop] — the 9:30 hard stop or an
  /// interruption by another app/call. [stop] returns the same value for a manual stop.
  Stream<PendingRecording> get completed => _completed.stream;

  final _completed = StreamController<PendingRecording>.broadcast();
  StreamSubscription<Duration>? _sub;
  String? _ticketId;
  bool _recording = false;
  Future<PendingRecording>? _finishing;

  Future<RecordingStartResult> start({String? ticketId}) async {
    if (_recording) return RecordingStartResult.started;
    if (!await consentAccepted()) return RecordingStartResult.consentRequired;
    switch (await permissions.request()) {
      case MicPermission.denied:
        return RecordingStartResult.permissionDenied;
      case MicPermission.permanentlyDenied:
        return RecordingStartResult.permissionPermanentlyDenied;
      case MicPermission.granted:
        break;
    }
    _ticketId = ticketId;
    await recorder.start();
    _recording = true;
    _finishing = null;
    _sub = recorder.elapsed.listen(
      (d) {
        if (d >= maxRecordingLength) _finishAndNotify();
      },
      onDone: _finishAndNotify,
    );
    return RecordingStartResult.started;
  }

  /// Stops and persists the recording (file + idempotency key) so it survives a failed upload.
  Future<PendingRecording> stop() => _finish();

  void _finishAndNotify() {
    if (!_recording) return;
    _finish().then(_completed.add, onError: _completed.addError);
  }

  Future<PendingRecording> _finish() {
    final inflight = _finishing;
    if (inflight != null) return inflight;
    if (!_recording) return Future.error(StateError('Nessuna registrazione in corso.'));
    return _finishing = () async {
      _recording = false;
      await _sub?.cancel();
      _sub = null;
      final file = await recorder.stop();
      return store.add(file, ticketId: _ticketId);
    }();
  }

  /// Uploads with the recording's OWN key. On success the local files are deleted; on any
  /// failure they are kept and the same call can simply be repeated.
  Future<AiTranscription> upload(PendingRecording pending) async {
    final result = await _uploader(pending.file, pending.idempotencyKey);
    await store.delete(pending);
    return result;
  }
}
