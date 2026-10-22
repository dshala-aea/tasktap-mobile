// dart format width=100
// techniciansProvider's two sources: the live `/api/users?role=Technician` list online, the synced
// `colleagues` mirror offline or when that call fails.
//
// The gap this pins: both technician pickers (new-ticket step 3 and the ticket-detail assign sheet)
// had no offline path, so a ticket created or reassigned on site fell back to "Nessuno" even though
// the tenant's colleagues were already mirrored on the device.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/ticket/steps/step_assegnazione.dart';
import 'package:tasktap_mobile/features/ticket/ticket_api_client.dart';

/// Stands in for the network. [error] makes the call fail; [calls] proves whether the provider
/// touched it at all.
class _FakeApiClient extends TicketApiClient {
  _FakeApiClient({this.result, this.error}) : super(Dio());

  final List<Map<String, dynamic>>? result;
  final Object? error;
  int calls = 0;

  @override
  Future<List<Map<String, dynamic>>> fetchTechnicians() async {
    calls++;
    final failure = error;
    if (failure != null) throw failure;
    return result ?? const [];
  }
}

void main() {
  late AppDatabase db;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  Future<void> seedColleagues() async {
    await db
        .into(db.colleagues)
        .insert(ColleaguesCompanion.insert(id: 'u1', displayName: 'Mario Rossi'));
    await db.into(db.colleagues).insert(ColleaguesCompanion.insert(id: 'u2', displayName: 'Anna'));
  }

  ProviderContainer container({required bool online, required _FakeApiClient api}) {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        isOnlineProvider.overrideWithValue(online),
        ticketApiClientProvider.overrideWithValue(api),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('offline it answers from the colleagues mirror and never calls the API', () async {
    await seedColleagues();
    final api = _FakeApiClient(error: StateError('the network must not be touched offline'));

    final techs = await container(online: false, api: api).read(techniciansProvider.future);

    expect(api.calls, 0);
    expect(techs.map((t) => t['id']), ['u2', 'u1'], reason: 'sorted by display name');
    // Both map shapes the two pickers read: the assignment step builds "firstName lastName", the
    // admin pickers read `displayName` directly.
    expect(techs.last['firstName'], 'Mario');
    expect(techs.last['lastName'], 'Rossi');
    expect(techs.last['displayName'], 'Mario Rossi');
    expect(techs.first['lastName'], '', reason: 'a one-word name has no surname to invent');
  });

  test('online the live list wins, never merged with the mirror', () async {
    await seedColleagues();
    final api = _FakeApiClient(
      result: [
        {'id': 'server-1', 'firstName': 'Luca', 'lastName': 'Bianchi'},
      ],
    );

    final techs = await container(online: true, api: api).read(techniciansProvider.future);

    expect(api.calls, 1);
    expect(techs.single['id'], 'server-1');
  });

  test('a failing live fetch falls back to the mirror instead of an empty picker', () async {
    await seedColleagues();
    final api = _FakeApiClient(error: StateError('radio off mid-request'));

    final techs = await container(online: true, api: api).read(techniciansProvider.future);

    expect(api.calls, 1);
    expect(techs.map((t) => t['id']), ['u2', 'u1']);
  });

  test('offline with an empty mirror the picker is empty, not an error', () async {
    final techs = await container(
      online: false,
      api: _FakeApiClient(error: StateError('unused')),
    ).read(techniciansProvider.future);

    expect(techs, isEmpty);
  });
}
