// dart format width=100
// Realistic bodies of `GET /api/worklog/active`, as the backend serializes them (camelCase, enums
// by name, ISO instants with a trailing Z and, for some, a 7-digit .NET fraction). Kept as raw
// JSON so tests exercise the real wire shape rather than hand-built Dart objects.
import 'dart:convert';

import 'package:tasktap_mobile/data/worklogs/active_tracker_api_client.dart';

const attendanceWorkingJson = '''
{"kind":"Attendance","id":"7c1f0e52-3b0a-4d6e-9d0a-1f5b7a1c2d01","startedAtUtc":"2026-09-30T08:23:45.1234567Z","label":null,"entityId":null,"userId":null,"userName":null,"state":"Working","shiftStartedAtUtc":"2026-09-30T08:23:45.1234567Z"}''';

const attendanceOnBreakJson = '''
{"kind":"Attendance","id":"7c1f0e52-3b0a-4d6e-9d0a-1f5b7a1c2d02","startedAtUtc":"2026-09-30T11:02:10Z","label":null,"entityId":null,"userId":null,"userName":null,"state":"OnBreak","shiftStartedAtUtc":"2026-09-30T08:23:45Z"}''';

const cantiereJson = '''
{"kind":"Cantiere","id":"0b4c9a3e-6f2d-4a51-8f7e-2c9d1e3a4b05","startedAtUtc":"2026-09-30T09:00:00Z","label":"Cantiere Via Roma","entityId":"5d1e2f3a-4b5c-4d6e-8f70-819293a4b5c6","userId":null,"userName":null,"state":null,"shiftStartedAtUtc":null}''';

List<ActiveTracker> trackersFromWire(List<String> rows) {
  final decoded = jsonDecode('[${rows.join(',')}]') as List;
  return decoded.cast<Map<String, dynamic>>().map(ActiveTracker.fromJson).toList();
}
