// dart format width=100
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasktap_mobile/core/audio/audio_recorder_service.dart';
import 'package:tasktap_mobile/core/audio/pending_recording_store.dart';
import 'package:tasktap_mobile/core/audio/voice_capture_controller.dart';
import 'package:tasktap_mobile/core/audio/voice_consent.dart';
import 'package:tasktap_mobile/data/ai/ai_api_client.dart';
import 'package:tasktap_mobile/data/auth/session_ender.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/domain/auth/i_auth_repository.dart';
import 'package:drift/native.dart';

class _FakeRecorder implements AudioRecorderService {
  _FakeRecorder(this.dir);

  final Directory dir;
  final _elapsed = StreamController<Duration>.broadcast();
  bool started = false;
  int stops = 0;

  @override
  Future<void> start() async => started = true;

  /// When set, [stop] waits for it: the recording is "ending" (saved but not yet stored).
  Completer<void>? stopGate;

  @override
  Future<File> stop() async {
    final gate = stopGate;
    if (gate != null) await gate.future;
    stops++;
    started = false;
    final f = File('${dir.path}/rec_$stops.m4a');
    await f.writeAsBytes([1, 2, 3, 4]);
    return f;
  }

  @override
  Stream<Duration> get elapsed => _elapsed.stream;

  void tick(Duration d) => _elapsed.add(d);
  Future<void> endUnexpectedly() => _elapsed.close();
}

class _FakePermissions implements MicPermissionService {
  _FakePermissions(this.result);
  MicPermission result;
  int asked = 0;

  @override
  Future<MicPermission> request() async {
    asked++;
    return result;
  }
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.onFetch);
  final Future<ResponseBody> Function(RequestOptions, Stream<List<int>>?) onFetch;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) => onFetch(options, requestStream);
}

ResponseBody _json(int status, Object body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

AiApiClient _client(Future<ResponseBody> Function(RequestOptions, Stream<List<int>>?) f) {
  final dio = Dio();
  dio.httpClientAdapter = _Adapter(f);
  return AiApiClient(dio);
}

class _FakeAuth implements IAuthRepository {
  @override
  AuthUser? get currentUser => null;
  @override
  Stream<AuthUser?> get authStateChanges => const Stream.empty();
  @override
  Future<void> signOut() async {}
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

void main() {
  late Directory tmp;
  late PendingRecordingStore store;
  late _FakeRecorder recorder;
  late _FakePermissions perms;

  VoiceCaptureController controller({
    Future<AiVoiceCapture> Function(File, String)? upload,
    Future<bool> Function()? consent,
    String? user,
  }) => VoiceCaptureController(
    currentUserId: () => user ?? 'userA',
    recorder: recorder,
    permissions: perms,
    store: store,
    consentAccepted: consent ?? () async => true,
    upload: upload ?? (f, k) async => const AiVoiceCapture(audioRef: 'r', durationSeconds: 3),
  );

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('voice_test');
    store = PendingRecordingStore(Directory('${tmp.path}/pending'));
    recorder = _FakeRecorder(tmp);
    perms = _FakePermissions(MicPermission.granted);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test('Failed_upload_keeps_the_local_file_and_the_same_key_on_retry', () async {
    final keys = <String>[];
    var fail = true;
    final c = controller(
      upload: (f, k) async {
        keys.add(k);
        if (fail) throw const AiFailure('offline');
        return const AiVoiceCapture(audioRef: 'abc', durationSeconds: 8);
      },
    );
    await c.start(ticketId: 'T1');
    final pending = await c.stop();

    await expectLater(c.upload(pending), throwsA(isA<AiFailure>()));
    expect(pending.file.existsSync(), isTrue);
    expect(await store.list(userId: 'userA'), hasLength(1));

    fail = false;
    final result = await c.upload((await store.list(userId: 'userA')).single);
    expect(result.audioRef, 'abc');
    expect(keys, hasLength(2));
    expect(keys[0], keys[1]);
    expect(keys[0], pending.idempotencyKey);
  });

  test('Recording_is_refused_until_consent_is_accepted', () async {
    expect(await voiceConsentAccepted(), isFalse);
    final c = controller(consent: voiceConsentAccepted);

    expect(await c.start(ticketId: 'T1'), RecordingStartResult.consentRequired);
    expect(recorder.started, isFalse);
    expect(perms.asked, 0);

    await acceptVoiceConsent();
    expect(await voiceConsentAccepted(), isTrue);
    expect(await c.start(ticketId: 'T1'), RecordingStartResult.started);
    expect(recorder.started, isTrue);
    expect(voiceConsentText, isNotEmpty);
  });

  test('Permission_denied_is_reported_not_crashed', () async {
    final c = controller();
    perms.result = MicPermission.denied;
    expect(await c.start(ticketId: 'T1'), RecordingStartResult.permissionDenied);
    perms.result = MicPermission.permanentlyDenied;
    expect(await c.start(ticketId: 'T1'), RecordingStartResult.permissionPermanentlyDenied);
    expect(recorder.started, isFalse);
  });

  test('Auto_stop_at_the_maximum_length', () async {
    final c = controller();
    await c.start(ticketId: 'T1');
    final done = c.completed.first;

    recorder.tick(const Duration(minutes: 4, seconds: 59));
    await Future<void>.delayed(Duration.zero);
    expect(recorder.stops, 0);

    recorder.tick(maxRecordingLength);
    final pending = await done.timeout(const Duration(seconds: 2));
    expect(maxRecordingLength, const Duration(minutes: 5));
    expect(recorder.stops, 1);
    expect(pending.file.existsSync(), isTrue);
    expect(c.isRecording, isFalse);
  });

  test('Interrupted_recording_ends_cleanly_with_the_file_so_far', () async {
    final c = controller();
    await c.start(ticketId: 'T1');
    final done = c.completed.first;
    await recorder.endUnexpectedly();
    final pending = await done.timeout(const Duration(seconds: 2));
    expect(pending.file.existsSync(), isTrue);
    expect(recorder.stops, 1);
  });

  test('Cancel_stops_the_recorder_and_leaves_no_pending_file', () async {
    final c = controller();
    await c.start(ticketId: null);
    var completedEvents = 0;
    final sub = c.completed.listen((_) => completedEvents++);

    await c.cancel();
    await Future<void>.delayed(Duration.zero);

    expect(recorder.stops, 1);
    expect(recorder.started, isFalse);
    expect(c.isRecording, isFalse);
    expect(File('${tmp.path}/rec_1.m4a').existsSync(), isFalse, reason: 'the produced file is deleted');
    expect(await store.list(userId: 'userA'), isEmpty);
    expect(completedEvents, 0);
    // The 5-minute limit of the cancelled recording must not fire later.
    recorder.tick(maxRecordingLength);
    await Future<void>.delayed(Duration.zero);
    expect(recorder.stops, 1);
    await sub.cancel();
  });

  test('Cancel_when_idle_does_nothing', () async {
    final c = controller();
    await c.cancel();
    expect(recorder.stops, 0);
  });

  test('Start_over_a_stale_ticketless_recording_cancels_and_deletes_it', () async {
    final c = controller();
    expect(await c.start(ticketId: null), RecordingStartResult.started);
    expect(await c.start(ticketId: 'T2'), RecordingStartResult.started);
    expect(recorder.stops, 1, reason: 'the stale recording was stopped, not adopted');
    expect(File('${tmp.path}/rec_1.m4a').existsSync(), isFalse, reason: 'its file is deleted');
    expect(await store.list(userId: 'userA'), isEmpty);
    final pending = await c.stop();
    expect(pending.ticketId, 'T2');
    expect((await store.list(userId: 'userA')).map((r) => r.ticketId), ['T2']);
  });

  test('Start_over_a_stale_ticket_bound_recording_stops_and_keeps_it', () async {
    final c = controller();
    expect(await c.start(ticketId: 'T1'), RecordingStartResult.started);
    expect(await c.start(ticketId: 'T2'), RecordingStartResult.started);
    expect(recorder.stops, 1, reason: 'the stale recording was stopped, not adopted');
    final kept = (await store.list(userId: 'userA')).single;
    expect(kept.ticketId, 'T1', reason: 'kept under its OWN ticket, offered there next time');
    expect(kept.file.existsSync(), isTrue);
    final pending = await c.stop();
    expect(pending.ticketId, 'T2');
    expect((await store.list(userId: 'userA')).map((r) => r.ticketId).toSet(), {'T1', 'T2'});
  });

  test('Cancel_while_the_9_30_stop_is_saving_deletes_it_and_emits_nothing', () async {
    final c = controller();
    await c.start(ticketId: null);
    var completedEvents = 0;
    final sub = c.completed.listen((_) => completedEvents++, onError: (_) => completedEvents++);
    recorder.stopGate = Completer<void>();

    recorder.tick(maxRecordingLength);
    await Future<void>.delayed(Duration.zero);
    expect(c.isRecording, isFalse, reason: 'the auto-finish has begun');

    final cancelling = c.cancel();
    recorder.stopGate!.complete();
    await cancelling;
    await Future<void>.delayed(Duration.zero);

    expect(recorder.stops, 1);
    expect(File('${tmp.path}/rec_1.m4a').existsSync(), isFalse, reason: 'no ticketless file left');
    expect(await store.list(userId: 'userA'), isEmpty);
    expect(completedEvents, 0);
    await sub.cancel();
  });

  test('Cancel_after_a_recording_was_saved_never_deletes_it', () async {
    final c = controller();
    await c.start(ticketId: null);
    final saved = await c.stop();
    await c.cancel();
    expect(saved.file.existsSync(), isTrue);
    expect(await store.list(userId: 'userA'), hasLength(1));
  });

  test('Pending_recording_survives_a_store_reload', () async {
    final c = controller();
    await c.start(ticketId: 'T9');
    final pending = await c.stop();

    final reloaded = PendingRecordingStore(Directory('${tmp.path}/pending'));
    final list = await reloaded.list(userId: 'userA');
    expect(list, hasLength(1));
    expect(list.single.idempotencyKey, pending.idempotencyKey);
    expect(list.single.ticketId, 'T9');
    expect(list.single.createdAt.toUtc(), pending.createdAt.toUtc());
    expect(list.single.file.existsSync(), isTrue);
  });

  test('Successful_upload_deletes_the_pending_recording', () async {
    final c = controller();
    await c.start(ticketId: 'T1');
    final pending = await c.stop();
    await c.upload(pending);
    expect(await store.list(userId: 'userA'), isEmpty);
    expect(pending.file.existsSync(), isFalse);
  });

  test('User_B_never_sees_user_A_pending_recording', () async {
    final a = controller(user: 'userA');
    await a.start(ticketId: 'T1');
    final pending = await a.stop();
    expect(pending.userId, 'userA');

    expect(await store.list(userId: 'userB'), isEmpty);
    final b = controller(user: 'userB');
    await expectLater(b.upload(pending), throwsA(isA<StateError>()));
    expect(pending.file.existsSync(), isTrue);
    expect(await store.list(userId: 'userA'), hasLength(1));
  });

  test('Recordings_older_than_seven_days_are_deleted_on_list', () async {
    final c = controller();
    await c.start();
    final pending = await c.stop();
    final sidecar = File('${store.directory.path}/${pending.id}.json');
    final map = jsonDecode(await sidecar.readAsString()) as Map<String, dynamic>;
    map['createdAt'] = DateTime.now().toUtc().subtract(const Duration(days: 8)).toIso8601String();
    await sidecar.writeAsString(jsonEncode(map));

    expect(await store.list(userId: 'userA'), isEmpty);
    expect(pending.file.existsSync(), isFalse);
    expect(sidecar.existsSync(), isFalse);
  });

  test('Orphan_files_are_cleaned_but_only_once_old_enough', () async {
    await store.directory.create(recursive: true);
    final old = DateTime.now().subtract(const Duration(minutes: 30));
    final orphanAudio = File('${store.directory.path}/o1.m4a')..writeAsBytesSync([1]);
    final freshAudio = File('${store.directory.path}/o2.m4a')..writeAsBytesSync([1]);
    final orphanSidecar = File('${store.directory.path}/o3.json')..writeAsStringSync('{}');
    await orphanAudio.setLastModified(old);
    await orphanSidecar.setLastModified(old);

    expect(await store.list(userId: 'userA'), isEmpty);
    expect(orphanAudio.existsSync(), isFalse);
    expect(orphanSidecar.existsSync(), isFalse);
    expect(freshAudio.existsSync(), isTrue); // may belong to an add() still in flight
  });

  test('Logout_removes_the_pending_directory', () async {
    final c = controller();
    await c.start();
    await c.stop();
    expect(store.directory.existsSync(), isTrue);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    SharedPreferences.setMockInitialValues({'x': true});
    var zoneReset = false;
    final ender = SessionEnder(
      repo: _FakeAuth(),
      db: db,
      resetBusinessZone: () async => zoneReset = true,
      wipePendingVoice: store.wipe,
    );
    await ender.end();

    expect(store.directory.existsSync(), isFalse);
    expect(zoneReset, isTrue);

    // best-effort: a failing wipe must not stop the rest of the teardown.
    zoneReset = false;
    await SessionEnder(
      repo: _FakeAuth(),
      db: db,
      resetBusinessZone: () async => zoneReset = true,
      wipePendingVoice: () async => throw const FileSystemException('boom'),
    ).end();
    expect(zoneReset, isTrue);
  });

  group('AiApiClient.uploadVoiceCapture', () {
    late File audio;
    setUp(() async {
      audio = File('${tmp.path}/a.m4a')..writeAsBytesSync(List.filled(64, 7));
    });

    test('uploadVoiceCapture_sends_the_idempotency_key_header_and_audio_part', () async {
      late RequestOptions seen;
      final client = _client((o, body) async {
        seen = o;
        return _json(200, {'audioRef': 'ref-1', 'durationSeconds': 42});
      });

      final r = await client.uploadVoiceCapture(audio, idempotencyKey: 'key-123');

      expect(r.audioRef, 'ref-1');
      expect(r.durationSeconds, 42);
      expect(seen.path, '/api/ai/voice-captures');
      expect(seen.method, 'POST');
      expect(seen.headers['Idempotency-Key'], 'key-123');
      expect(seen.sendTimeout, voiceUploadSendTimeout);
      expect(seen.receiveTimeout, voiceUploadReceiveTimeout);
      expect(seen.headers['content-type'] ?? seen.contentType, startsWith('multipart/form-data'));
      expect(seen.headers['content-type'] ?? seen.contentType, contains('boundary='));
      final form = seen.data as FormData;
      expect(form.files.single.key, 'audio');
      expect(form.files.single.value.contentType.toString(), 'audio/mp4');
    });

    test('uploadVoiceCapture_maps_server_error_codes_to_typed_exceptions', () async {
      Future<Object?> run(int status, Object body) async {
        final client = _client((o, b) async => _json(status, body));
        try {
          await client.uploadVoiceCapture(audio, idempotencyKey: 'k');
        } catch (e) {
          return e;
        }
        return null;
      }

      AiVoiceUploadError reason(Object? e) => (e as AiVoiceUploadException).error;

      expect(
        reason(await run(400, {'error': 'audio_type_mismatch', 'message': 'x'})),
        AiVoiceUploadError.audioTypeMismatch,
      );
      expect(
        reason(await run(400, {'error': 'audio_unrecognised', 'message': 'x'})),
        AiVoiceUploadError.audioUnrecognised,
      );
      expect(
        reason(await run(400, {'error': 'audio_too_long', 'message': 'x'})),
        AiVoiceUploadError.audioTooLong,
      );
      expect(
        reason(await run(400, {'error': 'audio_too_short', 'message': 'x'})),
        AiVoiceUploadError.audioTooShort,
      );
      expect(
        reason(await run(400, {'error': 'audio_too_large', 'message': 'x'})),
        AiVoiceUploadError.audioTooLarge,
      );
      expect(reason(await run(404, {})), AiVoiceUploadError.voiceDisabled);
      expect(
        reason(
          await run(403, {
            'error': 'La generazione di bozze con AI è disattivata per questa azienda.',
          }),
        ),
        AiVoiceUploadError.aiDisabled,
      );
      expect(reason(await run(403, {'error': 'Forbidden'})), AiVoiceUploadError.forbidden);
      expect(reason(await run(403, {})), AiVoiceUploadError.forbidden);
      expect(reason(await run(413, {})), AiVoiceUploadError.audioTooLarge);
      expect(reason(await run(400, {'error': 'weird'})), AiVoiceUploadError.badRequest);
      expect(reason(await run(400, 'bare string')), AiVoiceUploadError.badRequest);
      for (final e in [
        AiVoiceUploadError.audioTooLarge,
        AiVoiceUploadError.badRequest,
        AiVoiceUploadError.forbidden,
        AiVoiceUploadError.aiDisabled,
        AiVoiceUploadError.voiceDisabled,
      ]) {
        expect(AiVoiceUploadException(e, '').retryable, isFalse, reason: '$e');
      }
      expect(reason(await run(500, {})), AiVoiceUploadError.unavailable);
      expect(await run(429, {'error': 'QuotaExceeded'}), isA<AiQuotaExhaustedException>());

      for (final t in [DioExceptionType.receiveTimeout, DioExceptionType.sendTimeout]) {
        final slow = _client((o, b) async => throw DioException(requestOptions: o, type: t));
        Object? err;
        try {
          await slow.uploadVoiceCapture(audio, idempotencyKey: 'k');
        } catch (e) {
          err = e;
        }
        expect(reason(err), AiVoiceUploadError.timeout, reason: '$t');
        expect((err as AiVoiceUploadException).retryable, isTrue);
      }

      final offline = _client(
        (o, b) async => throw DioException(
          requestOptions: o,
          type: DioExceptionType.connectionError,
        ),
      );
      await expectLater(
        offline.uploadVoiceCapture(audio, idempotencyKey: 'k'),
        throwsA(
          isA<AiVoiceUploadException>().having(
            (e) => e.error,
            'error',
            AiVoiceUploadError.offline,
          ),
        ),
      );
    });
  });
}
