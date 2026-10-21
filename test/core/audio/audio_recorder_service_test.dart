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

class _FakeRecorder implements AudioRecorderService {
  _FakeRecorder(this.dir);

  final Directory dir;
  final _elapsed = StreamController<Duration>.broadcast();
  bool started = false;
  int stops = 0;

  @override
  Future<void> start() async => started = true;

  @override
  Future<File> stop() async {
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

void main() {
  late Directory tmp;
  late PendingRecordingStore store;
  late _FakeRecorder recorder;
  late _FakePermissions perms;

  VoiceCaptureController controller({
    Future<AiTranscription> Function(File, String)? upload,
    Future<bool> Function()? consent,
  }) => VoiceCaptureController(
    recorder: recorder,
    permissions: perms,
    store: store,
    consentAccepted: consent ?? () async => true,
    upload: upload ?? (f, k) async => const AiTranscription(transcript: 't', audioRef: 'r'),
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
        return const AiTranscription(transcript: 'ciao', audioRef: 'abc');
      },
    );
    await c.start(ticketId: 'T1');
    final pending = await c.stop();

    await expectLater(c.upload(pending), throwsA(isA<AiFailure>()));
    expect(pending.file.existsSync(), isTrue);
    expect(await store.list(), hasLength(1));

    fail = false;
    final result = await c.upload((await store.list()).single);
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

    recorder.tick(const Duration(minutes: 9, seconds: 29));
    await Future<void>.delayed(Duration.zero);
    expect(recorder.stops, 0);

    recorder.tick(maxRecordingLength);
    final pending = await done.timeout(const Duration(seconds: 2));
    expect(maxRecordingLength, const Duration(minutes: 9, seconds: 30));
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

  test('Pending_recording_survives_a_store_reload', () async {
    final c = controller();
    await c.start(ticketId: 'T9');
    final pending = await c.stop();

    final reloaded = PendingRecordingStore(Directory('${tmp.path}/pending'));
    final list = await reloaded.list();
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
    expect(await store.list(), isEmpty);
    expect(pending.file.existsSync(), isFalse);
  });

  group('AiApiClient.transcribe', () {
    late File audio;
    setUp(() async {
      audio = File('${tmp.path}/a.m4a')..writeAsBytesSync(List.filled(64, 7));
    });

    test('transcribe_sends_the_idempotency_key_header_and_audio_part', () async {
      late RequestOptions seen;
      final client = _client((o, body) async {
        seen = o;
        return _json(200, {'transcript': 'ciao mondo', 'audioRef': 'ref-1'});
      });

      final r = await client.transcribe(audio, idempotencyKey: 'key-123');

      expect(r.transcript, 'ciao mondo');
      expect(r.audioRef, 'ref-1');
      expect(seen.path, '/api/ai/transcribe');
      expect(seen.method, 'POST');
      expect(seen.headers['Idempotency-Key'], 'key-123');
      final form = seen.data as FormData;
      expect(form.files.single.key, 'audio');
      expect(form.files.single.value.contentType.toString(), 'audio/mp4');
    });

    test('transcribe_maps_server_error_codes_to_typed_exceptions', () async {
      Future<Object?> run(int status, Object body) async {
        final client = _client((o, b) async => _json(status, body));
        try {
          await client.transcribe(audio, idempotencyKey: 'k');
        } catch (e) {
          return e;
        }
        return null;
      }

      AiTranscribeError reason(Object? e) => (e as AiTranscribeException).error;

      expect(
        reason(await run(400, {'error': 'audio_type_mismatch', 'message': 'x'})),
        AiTranscribeError.audioTypeMismatch,
      );
      expect(
        reason(await run(400, {'error': 'audio_unrecognised', 'message': 'x'})),
        AiTranscribeError.audioUnrecognised,
      );
      expect(
        reason(await run(400, {'error': 'audio_too_long', 'message': 'x'})),
        AiTranscribeError.audioTooLong,
      );
      expect(
        reason(await run(400, {'error': 'audio_too_short', 'message': 'x'})),
        AiTranscribeError.audioTooShort,
      );
      expect(
        reason(await run(400, {'error': 'audio_too_large', 'message': 'x'})),
        AiTranscribeError.audioTooLarge,
      );
      expect(reason(await run(404, {})), AiTranscribeError.voiceDisabled);
      expect(reason(await run(403, {'error': 'x'})), AiTranscribeError.aiDisabled);
      expect(reason(await run(500, {})), AiTranscribeError.unavailable);
      expect(await run(429, {'error': 'QuotaExceeded'}), isA<AiQuotaExhaustedException>());

      final offline = _client(
        (o, b) async => throw DioException(
          requestOptions: o,
          type: DioExceptionType.connectionError,
        ),
      );
      await expectLater(
        offline.transcribe(audio, idempotencyKey: 'k'),
        throwsA(
          isA<AiTranscribeException>().having(
            (e) => e.error,
            'error',
            AiTranscribeError.offline,
          ),
        ),
      );
    });
  });
}
