// test/features/rapportino/steps/recent_work_log_provider_test.dart
//
// recentWorkLogProvider (StepOre's third suggestion tier) fetches the last 30 days of the user's
// plain timbrature. The window is a pair of date labels in the legacy (Rome) frame, so it must
// follow the business clock and never the device zone: run under TZ=America/Los_Angeles or
// Pacific/Auckland (tool/test_tz_matrix.sh) the assertions below are identical.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/core/time/business_time_providers.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/timbratura/worklog_api_client.dart';
import 'package:tasktap_mobile/features/rapportino/steps/step_ore.dart';

class _RecordingApi extends WorklogApiClient {
  _RecordingApi() : super(Dio());

  final List<({String userId, DateTime from, DateTime to})> calls = [];

  @override
  Future<List<UserWorkLogDto>> fetchForUser({
    required String userId,
    required DateTime dateFrom,
    required DateTime dateTo,
  }) async {
    calls.add((userId: userId, from: dateFrom, to: dateTo));
    return const [];
  }
}

({_RecordingApi api, ProviderContainer container}) _setup({
  required DateTime clock,
  String zone = 'Europe/Rome',
  bool online = true,
}) {
  final api = _RecordingApi();
  final container = ProviderContainer(
    overrides: [
      worklogApiClientProvider.overrideWithValue(api),
      isOnlineProvider.overrideWithValue(online),
      clockProvider.overrideWithValue(() => clock),
      businessZoneIdProvider.overrideWith(() => _FixedZone(zone)),
    ],
  );
  addTearDown(container.dispose);
  return (api: api, container: container);
}

class _FixedZone extends BusinessZoneIdNotifier {
  _FixedZone(this._zone);
  final String _zone;

  @override
  String build() => _zone;
}

void main() {
  test('window is the 30 days ending on the Rome date', () async {
    final s = _setup(clock: DateTime.utc(2026, 7, 10, 12));
    await s.container.read(recentWorkLogProvider('user-1').future);

    expect(s.api.calls, hasLength(1));
    final call = s.api.calls.single;
    expect(call.userId, 'user-1');
    expect((call.to.year, call.to.month, call.to.day), (2026, 7, 10));
    expect((call.from.year, call.from.month, call.from.day), (2026, 6, 10));
  });

  test('just after Rome midnight the window already ends on the next Rome date', () async {
    // 22:30Z on 10 July is 00:30 on 11 July in Rome but still 10 July in Los Angeles (15:30) and
    // 11 July in Auckland (10:30): only the Rome reading is right.
    final s = _setup(clock: DateTime.utc(2026, 7, 10, 22, 30));
    await s.container.read(recentWorkLogProvider('user-1').future);

    final call = s.api.calls.single;
    expect((call.to.year, call.to.month, call.to.day), (2026, 7, 11));
    expect((call.from.year, call.from.month, call.from.day), (2026, 6, 11));
  });

  test('just before Rome midnight the window still ends on the current Rome date', () async {
    // 21:30Z on 10 July is 23:30 on 10 July in Rome, already 11 July 09:30 in Auckland.
    final s = _setup(clock: DateTime.utc(2026, 7, 10, 21, 30));
    await s.container.read(recentWorkLogProvider('user-1').future);

    final call = s.api.calls.single;
    expect((call.to.year, call.to.month, call.to.day), (2026, 7, 10));
    expect((call.from.year, call.from.month, call.from.day), (2026, 6, 10));
  });

  test('the legacy frame is Rome even when the tenant zone is elsewhere', () async {
    // 22:30Z on 10 July is 18:30 on 10 July in New York but already 11 July in Rome.
    final s = _setup(clock: DateTime.utc(2026, 7, 10, 22, 30), zone: 'America/New_York');
    await s.container.read(recentWorkLogProvider('user-1').future);

    final call = s.api.calls.single;
    expect((call.to.year, call.to.month, call.to.day), (2026, 7, 11));
  });

  test('offline: no request, empty list', () async {
    final s = _setup(clock: DateTime.utc(2026, 7, 10, 12), online: false);
    final result = await s.container.read(recentWorkLogProvider('user-1').future);

    expect(result, isEmpty);
    expect(s.api.calls, isEmpty);
  });
}
