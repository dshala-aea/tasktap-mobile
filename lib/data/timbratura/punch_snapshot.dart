// dart format width=100
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The server's `Idle | Working | OnBreak`.
enum PunchStatus {
  idle,
  working,
  onBreak;

  static PunchStatus parse(String? raw) => switch (raw) {
    'Working' => PunchStatus.working,
    'OnBreak' => PunchStatus.onBreak,
    _ => PunchStatus.idle,
  };

  String get wire => switch (this) {
    PunchStatus.idle => 'Idle',
    PunchStatus.working => 'Working',
    PunchStatus.onBreak => 'OnBreak',
  };
}

/// The server's last answer about the caller's shift (`state` of `POST /worklog/punches` or
/// `GET /worklog/state`). The phone shows this, with the taps the server has not answered yet laid
/// on top (see `projectPunchState`); it never infers the state itself (EPIC 29 design §6).
class PunchSnapshot {
  const PunchSnapshot({
    required this.status,
    this.shiftStartedAtUtc,
    this.breakStartedAtUtc,
    this.headAtUtc,
  });

  final PunchStatus status;
  final DateTime? shiftStartedAtUtc;
  final DateTime? breakStartedAtUtc;

  /// The instant of the newest event on the server's timeline: a tap older than this is superseded.
  final DateTime? headAtUtc;

  factory PunchSnapshot.fromJson(Map<String, dynamic> j) => PunchSnapshot(
    status: PunchStatus.parse(j['status'] as String?),
    shiftStartedAtUtc: _utc(j['shiftStartedAtUtc']),
    breakStartedAtUtc: _utc(j['breakStartedAtUtc']),
    headAtUtc: _utc(j['headAtUtc']),
  );

  Map<String, dynamic> toJson() => {
    'status': status.wire,
    'shiftStartedAtUtc': shiftStartedAtUtc?.toIso8601String(),
    'breakStartedAtUtc': breakStartedAtUtc?.toIso8601String(),
    'headAtUtc': headAtUtc?.toIso8601String(),
  };

  static DateTime? _utc(Object? v) => v is String ? DateTime.tryParse(v)?.toUtc() : null;
}

/// Remembers the last [PunchSnapshot] so a cold start with no network still shows what the server
/// last said. Keyed by the session id, like [PunchPipelineFlag]: a shared van/tablet can be signed
/// into another tenant next, and one person's shift must never be shown to the next.
class PunchSnapshotStore {
  PunchSnapshotStore({Future<SharedPreferences> Function()? prefs})
    : _prefs = prefs ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _prefs;

  static String keyFor(String sessionId) => 'tasktap.punchSnapshot.$sessionId';

  Future<PunchSnapshot?> read(String? sessionId) async {
    if (sessionId == null) return null;
    try {
      final raw = (await _prefs()).getString(keyFor(sessionId));
      if (raw == null) return null;
      return PunchSnapshot.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String sessionId, PunchSnapshot snapshot) async {
    try {
      await (await _prefs()).setString(keyFor(sessionId), jsonEncode(snapshot.toJson()));
    } catch (_) {
      // Not remembering it only means the next cold start asks the server again.
    }
  }
}
