// dart format width=100
// ticketControlsProvider's two axes: the live fetch online, the sync mirror offline and as the
// fallback when the live fetch fails.
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/ticket/ticket_detail_api_client.dart';
import 'package:tasktap_mobile/features/ticket/ticket_providers.dart';

/// Stands in for the network. [error] makes any call fail; [calls] proves whether the provider
/// touched the network at all (an offline read must leave it at zero).
class _FakeApiClient extends TicketDetailApiClient {
  _FakeApiClient({this.result, this.error}) : super(Dio());

  final List<TicketControlGroupDto>? result;
  final Object? error;
  int calls = 0;

  @override
  Future<List<TicketControlGroupDto>> fetchControls(String ticketId) async {
    calls++;
    final failure = error;
    if (failure != null) throw failure;
    return result ?? const [];
  }
}

TicketControlGroupDto _liveTree() => const TicketControlGroupDto(
  id: 'live',
  name: 'Dal server',
  sortOrder: 0,
  controls: [
    TicketControlDto(
      id: 'live-c1',
      templateControlId: 'tpl-live',
      label: 'Solo dal server',
      type: ControlType.checkbox,
      isRequired: false,
      sortOrder: 0,
      status: 'Pending',
    ),
  ],
);

void main() {
  late AppDatabase db;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  /// One ticket-level control, as a sync would have left it in the mirror.
  Future<void> seedMirror({String label = 'Dal mirror'}) async {
    await db
        .into(db.controlGroups)
        .insert(
          ControlGroupsCompanion.insert(
            id: 'g',
            maintenanceTemplateVersionId: 'v1',
            name: 'Sicurezza',
            sortOrder: 0,
          ),
        );
    await db
        .into(db.ticketControls)
        .insert(
          TicketControlsCompanion.insert(
            id: 'tl-1',
            ticketId: 'ticket-1',
            templateControlId: 'tpl-tl',
            controlLineageId: 'lin-tl',
            groupId: 'g',
            label: label,
            type: 'Checkbox',
            isRequired: const Value(true),
          ),
        );
  }

  ProviderContainer buildContainer({
    required bool online,
    required _FakeApiClient api,
  }) => ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      isOnlineProvider.overrideWithValue(online),
      ticketDetailApiClientProvider.overrideWithValue(api),
    ],
  );

  test('offline answers from the mirror and never calls the API', () async {
    await seedMirror();
    final api = _FakeApiClient(error: StateError('the network must not be touched offline'));
    final container = buildContainer(online: false, api: api);
    addTearDown(container.dispose);

    final groups = await container.read(ticketControlsProvider('ticket-1').future);

    expect(api.calls, 0);
    expect(groups.single.name, 'Sicurezza');
    expect(groups.single.controls.single.label, 'Dal mirror');
    expect(groups.single.controls.single.prodottoAssistenzaId, isNull);
  });

  test('online the live answer wins, never merged with the mirror', () async {
    await seedMirror(label: 'Solo dal mirror');
    final api = _FakeApiClient(result: [_liveTree()]);
    final container = buildContainer(online: true, api: api);
    addTearDown(container.dispose);

    final groups = await container.read(ticketControlsProvider('ticket-1').future);

    expect(api.calls, 1);
    expect(groups.single.name, 'Dal server');
    expect(groups.single.controls.map((c) => c.label), ['Solo dal server']);
  });

  test('a throwing live fetch falls back to the mirror instead of an error screen', () async {
    await seedMirror();
    final api = _FakeApiClient(error: StateError('radio off mid-request'));
    final container = buildContainer(online: true, api: api);
    addTearDown(container.dispose);

    final groups = await container.read(ticketControlsProvider('ticket-1').future);

    expect(api.calls, 1);
    expect(groups.single.controls.single.label, 'Dal mirror');
  });

  test('a throwing live fetch with an empty mirror reports offline, never an empty checklist', () async {
    // The mirror cannot tell "no template" from "not synced yet", so answering `[]` here would let
    // the Controllo tab state that no controls are planned for a ticket whose checklist simply
    // never reached this phone.
    final api = _FakeApiClient(error: StateError('radio off mid-request'));
    final container = buildContainer(online: true, api: api);
    addTearDown(container.dispose);

    await expectLater(
      container.read(ticketControlsProvider('ticket-1').future),
      throwsA(isA<TicketDetailOfflineException>()),
    );
  });
}
