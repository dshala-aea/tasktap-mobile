// dart format width=100
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../presentation/providers/auth_providers.dart' show authStateProvider;

/// Whether this tenant's phones send punches through the unified pipeline
/// (`POST /api/worklog/punches`, EPIC 29) instead of the legacy interval batch.
///
/// A platform operator switches it per tenant; the phone learns it from `/api/Auth/me`
/// (`punchPipeline`) and keeps it here so a cold start with no network still knows which path
/// the queued taps belong to. Keyed by the session id: a shared van/tablet can be signed into
/// another tenant next, and one tenant's answer must never decide for the next person.
///
/// Absent, unreadable or false all mean the legacy path: the safe default, and exactly what an
/// older server (which does not send the key) gets.
class PunchPipelineFlag {
  PunchPipelineFlag({Future<SharedPreferences> Function()? prefs})
    : _prefs = prefs ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _prefs;

  final _changes = StreamController<(String, bool)>.broadcast();

  /// The flag for [sessionId] now, then again whenever `/auth/me` changes it, so the screen switches
  /// path without waiting for a restart.
  Stream<bool> watch(String? sessionId) {
    // A controller, not an async* generator: a generator suspended on an inner `await for` only sees a
    // cancel at its next yield, so the provider dispose would hang and the subscription would linger.
    late final StreamController<bool> controller;
    StreamSubscription<(String, bool)>? changes;
    controller = StreamController<bool>(
      onListen: () async {
        // Listen first, then read: a change that lands during the read must not be lost.
        if (sessionId != null) {
          changes = _changes.stream
              .where((c) => c.$1 == sessionId)
              .listen((c) => controller.add(c.$2));
        }
        final current = await read(sessionId);
        if (!controller.isClosed) controller.add(current);
        if (sessionId == null && !controller.isClosed) await controller.close();
      },
      onCancel: () async => changes?.cancel(),
    );
    return controller.stream;
  }

  static String keyFor(String sessionId) => 'tasktap.punchPipeline.$sessionId';

  Future<bool> read(String? sessionId) async {
    if (sessionId == null) return false;
    try {
      return (await _prefs()).getBool(keyFor(sessionId)) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> write(String sessionId, bool enabled) async {
    try {
      await (await _prefs()).setBool(keyFor(sessionId), enabled);
      _changes.add((sessionId, enabled));
    } catch (_) {
      // Not being able to remember it only means the next cold start asks /me again.
    }
  }
}

final punchPipelineFlagProvider = Provider<PunchPipelineFlag>((ref) => PunchPipelineFlag());

/// Whether the signed-in session is on the unified pipeline, as a value the UI can watch: it switches
/// when the server's answer changes, and is false (the legacy path) until it is known.
final punchPipelineActiveProvider = StreamProvider.autoDispose<bool>((ref) {
  final user = ref.watch(authStateProvider).value;
  return ref.watch(punchPipelineFlagProvider).watch(user?.id);
});

/// Reads the flag for the signed-in session at the moment of use (sync and tap time), never cached
/// across a sign-out.
final punchPipelineEnabledReaderProvider = Provider<Future<bool> Function()>((ref) {
  return () async {
    final user = ref.read(authStateProvider).value;
    return ref.read(punchPipelineFlagProvider).read(user?.id);
  };
});
