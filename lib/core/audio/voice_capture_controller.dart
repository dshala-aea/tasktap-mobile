// dart format width=100
import 'dart:async';
import 'dart:io';

import '../../data/ai/ai_api_client.dart';
import 'audio_recorder_service.dart';
import 'pending_recording_store.dart';

enum RecordingStartResult {
  started,
  consentRequired,
  notSignedIn,
  permissionDenied,
  permissionPermanentlyDenied,
}

/// Orchestrates one voice update: consent, then microphone permission, then record, persist,
/// upload. Every refusal is a returned [RecordingStartResult], never an exception.
class VoiceCaptureController {
  VoiceCaptureController({
    required this.recorder,
    required this.permissions,
    required this.store,
    required this.consentAccepted,
    required this.currentUserId,
    required Future<AiTranscription> Function(File audio, String idempotencyKey) upload,
  }) : _uploader = upload;

  final AudioRecorderService recorder;
  final MicPermissionService permissions;
  final PendingRecordingStore store;
  final Future<bool> Function() consentAccepted;

  /// The signed-in user, or null when signed out (recording is then refused).
  final String? Function() currentUserId;
  final Future<AiTranscription> Function(File audio, String idempotencyKey) _uploader;

  bool get isRecording => _recording;

  /// Emits the saved recording when it ended without [stop] — the 9:30 hard stop or an
  /// interruption by another app/call. [stop] returns the same value for a manual stop.
  Stream<PendingRecording> get completed => _completed.stream;

  final _completed = StreamController<PendingRecording>.broadcast();
  StreamSubscription<Duration>? _sub;
  String? _ticketId;
  String? _userId;
  bool _recording = false;
  Future<PendingRecording>? _finishing;

  /// The [_finishing] a [cancel] abandoned: its result is deleted, never emitted on [completed].
  Future<PendingRecording>? _discarded;

  Future<RecordingStartResult> start({String? ticketId}) async {
    // A recording still running here belongs to a screen that is gone (a screen only calls start
    // when it is not recording itself): never adopt it, it carries the old ticket id. Release it by
    // the screens' own rule: a ticket-bound one is stopped and KEPT (offered again on that ticket),
    // a ticketless one could never be offered again, so it is cancelled and deleted.
    if (_recording) {
      if (_ticketId != null) {
        try {
          await _finish();
        } catch (_) {
          // The recorder may already have ended; whatever it saved stays in the store.
        }
      } else {
        await cancel();
      }
    }
    // A recording still being saved (9:30 stop, interruption) finishes before the recorder restarts.
    final ending = _finishing;
    if (ending != null) await ending.then((_) {}, onError: (_) {});
    if (currentUserId() == null) return RecordingStartResult.notSignedIn;
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
    _userId = currentUserId();
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

  /// Abandons the recording in progress: stops the recorder, closes its subscription, resets the
  /// recording state and deletes the file it produced. Nothing is saved and nothing is emitted on
  /// [completed]. A recording that is already ENDING (the 9:30 stop or an interruption fired, or a
  /// [stop] is in flight) is still abandoned: once it is saved it is deleted again and not emitted.
  /// A no-op when idle or once a recording has been fully saved.
  Future<void> cancel() async {
    if (!_recording) {
      final ending = _finishing;
      if (ending == null) return;
      _discarded = ending;
      try {
        await store.delete(await ending);
      } catch (_) {
        // The recorder failed while ending: nothing was saved, so there is nothing to delete.
      }
      return;
    }
    _recording = false;
    final sub = _sub;
    _sub = null;
    _finishing = null;
    // Not awaited: nothing depends on the cancel completing.
    unawaited(sub?.cancel());
    try {
      final file = await recorder.stop();
      if (await file.exists()) await file.delete();
    } catch (_) {
      // The recorder may already have ended (interruption); there is nothing to release.
    }
  }

  /// Stops and persists the recording (file + idempotency key) so it survives a failed upload.
  Future<PendingRecording> stop() => _finish();

  void _finishAndNotify() {
    if (!_recording) return;
    final ending = _finish();
    // A [cancel] that arrived while this was being saved has deleted it again: not emitted.
    ending.then(
      (r) {
        if (!identical(_discarded, ending)) _completed.add(r);
      },
      onError: (Object e, StackTrace st) {
        if (!identical(_discarded, ending)) _completed.addError(e, st);
      },
    );
  }

  Future<PendingRecording> _finish() {
    final inflight = _finishing;
    if (inflight != null) return inflight;
    if (!_recording) return Future.error(StateError('Nessuna registrazione in corso.'));
    late final Future<PendingRecording> ending;
    ending = () async {
      try {
        _recording = false;
        await _sub?.cancel();
        _sub = null;
        final file = await recorder.stop();
        return await store.add(file, userId: _userId!, ticketId: _ticketId);
      } finally {
        // Only while it is in flight: a later [cancel] must never delete a recording that was
        // already saved and handed to its caller.
        if (identical(_finishing, ending)) _finishing = null;
      }
    }();
    return _finishing = ending;
  }

  /// Pending recordings of the current user only.
  Future<List<PendingRecording>> pendingForCurrentUser() async {
    final u = currentUserId();
    return u == null ? const [] : store.list(userId: u);
  }

  /// Transcribes with the recording's OWN key and KEEPS the local files. The server replays a
  /// repeated key (same transcript and `audioRef`, no new charge), so this is safe to repeat after a
  /// restart. The caller deletes the recording only once the turn built from it was accepted.
  Future<AiTranscription> transcribe(PendingRecording pending) async {
    if (pending.userId != currentUserId()) {
      throw StateError('Questa registrazione appartiene a un altro utente.');
    }
    return _uploader(pending.file, pending.idempotencyKey);
  }

  /// [transcribe], then delete the local files. On any failure they are kept. Prefer [transcribe]
  /// when the result still has to reach the server as a turn.
  Future<AiTranscription> upload(PendingRecording pending) async {
    final result = await transcribe(pending);
    await store.delete(pending);
    return result;
  }
}
