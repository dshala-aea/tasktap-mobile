// dart format width=100
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/ai/ai_api_client.dart';
import '../../presentation/providers/auth_providers.dart';
import 'audio_recorder_service.dart';
import 'pending_recording_store.dart';
import 'voice_capture_controller.dart';
import 'voice_consent.dart';

/// The online voice recorder, wired: consent gate, mic permission, recorder, the pending-upload
/// store and `AiApiClient.transcribe`. Resolved lazily (the store needs the documents directory),
/// so screens that never record never pay for it. NOT autoDispose: a screen reads it across
/// awaits without watching it, and an auto-disposed provider is torn down under that read.
///
/// `currentUserId` is the authenticated user's id, null when signed out (recording is then
/// refused). It is read at call time, so a sign-out mid-screen is honoured.
final voiceCaptureControllerProvider = FutureProvider<VoiceCaptureController>((ref) async {
  final store = await PendingRecordingStore.forApp();
  final client = ref.watch(aiApiClientProvider);
  final recorder = RecordAudioRecorderService();
  ref.onDispose(recorder.dispose);
  return VoiceCaptureController(
    recorder: recorder,
    permissions: const PermissionHandlerMicPermissionService(),
    store: store,
    consentAccepted: voiceConsentAccepted,
    currentUserId: () => ref.read(currentUserProvider)?.id,
    upload: (file, key) => client.transcribe(file, idempotencyKey: key),
  );
});
