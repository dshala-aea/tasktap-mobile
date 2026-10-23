// The rapportino material line's source, offline: `magazziniProvider` and `furgoneDiUserProvider`.
//
// Both were pure REST reads, so with no signal the add-material dialog opened with no default van
// and the "cambia magazzino" picker errored — the line was saved with a null magazzino and the
// report lost which warehouse the part came from.
//
// Online each one still reads through: criterion 1 is that a connected device shows the server's
// copy, never a mirror that may be a sync behind. Offline they answer from the `magazzini` mirror,
// and an empty mirror on a device that never synced is reported as "not downloaded yet" rather
// than as an empty tenant (a *synced* empty mirror is the tenant's real, empty answer).

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/magazzino/magazzino_api_client.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/magazzino/magazzino_providers.dart';

/// Stands in for the network. [calls] proves whether the provider touched it at all — an offline
/// read must leave it at zero.
class _FakeApiClient extends MagazzinoApiClient {
  _FakeApiClient({this.magazzini, this.furgone, this.error}) : super(Dio());

  final List<MagazzinoDto>? magazzini;
  final MagazzinoDto? furgone;
  final Object? error;
  int calls = 0;

  @override
  Future<List<MagazzinoDto>> getMagazzini({bool? isActive, String? tipo}) async {
    calls++;
    final failure = error;
    if (failure != null) throw failure;
    return magazzini ?? const [];
  }

  @override
  Future<MagazzinoDto?> getFurgoneByUser(String userId) async {
    calls++;
    final failure = error;
    if (failure != null) throw failure;
    return furgone;
  }
}

const _liveSede = MagazzinoDto(
  id: 'live-w',
  nome: 'Solo dal server',
  tipo: 'Sede',
  isActive: true,
);

void main() {
  late AppDatabase db;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  /// Mirrors as a sync would leave them.
  Future<void> seedMirror() async {
    await db
        .into(db.magazzini)
        .insert(
          MagazziniCompanion.insert(
            id: 'w-sede',
            tenantId: 'ten1',
            createdAt: DateTime.utc(2026, 10, 1),
            nome: 'Sede Milano',
            tipo: 'Sede',
          ),
        );
    await db
        .into(db.magazzini)
        .insert(
          MagazziniCompanion.insert(
            id: 'w-van',
            tenantId: 'ten1',
            createdAt: DateTime.utc(2026, 10, 1),
            nome: 'Furgone Rossi',
            tipo: 'Furgone',
            assegnatoUserId: const Value('u1'),
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
      magazzinoApiClientProvider.overrideWithValue(api),
    ],
  );

  group('magazziniProvider', () {
    test('offline lists the mirror alphabetically and never calls the API', () async {
      await seedMirror();
      final api = _FakeApiClient(
        error: StateError('the network must not be touched offline'),
      );
      final container = buildContainer(online: false, api: api);
      addTearDown(container.dispose);

      final list = await container.read(magazziniProvider.future);

      expect(api.calls, 0);
      expect(list.map((m) => m.nome), ['Furgone Rossi', 'Sede Milano']);
      expect(list.map((m) => m.tipo), ['Furgone', 'Sede']);
    });

    test('offline with an empty mirror reports "not downloaded", never an empty tenant', () async {
      final api = _FakeApiClient();
      final container = buildContainer(online: false, api: api);
      addTearDown(container.dispose);

      // The picker renders an empty list as "Nessun magazzino disponibile." — a claim about the
      // tenant's stock that would be false here.
      await expectLater(
        container.read(magazziniProvider.future),
        throwsA(isA<MagazziniOfflineException>()),
      );
      expect(api.calls, 0);
    });

    test('a synced-but-empty mirror is the tenant\'s real answer, not "not downloaded"', () async {
      // Something synced (so the device has seen the tenant) and the tenant has no warehouses —
      // the picker's plain empty state is then the truth, not the download warning.
      await db.setLastSync(DateTime.utc(2026, 10, 1));
      final api = _FakeApiClient();
      final container = buildContainer(online: false, api: api);
      addTearDown(container.dispose);

      expect(await container.read(magazziniProvider.future), isEmpty);
      expect(api.calls, 0);
    });

    test('online, a request that never arrived falls back to the mirror', () async {
      await seedMirror();
      final api = _FakeApiClient(
        error: DioException(
          requestOptions: RequestOptions(path: '/api/magazzini'),
          type: DioExceptionType.connectionTimeout,
        ),
      );
      final container = buildContainer(online: true, api: api);
      addTearDown(container.dispose);

      final list = await container.read(magazziniProvider.future);

      expect(api.calls, 1);
      expect(list.map((m) => m.nome), ['Furgone Rossi', 'Sede Milano']);
    });

    test('online, a 403 is about the account and is not papered over with the mirror', () async {
      await seedMirror();
      final api = _FakeApiClient(
        error: DioException(
          requestOptions: RequestOptions(path: '/api/magazzini'),
          response: Response(
            requestOptions: RequestOptions(path: '/api/magazzini'),
            statusCode: 403,
          ),
          type: DioExceptionType.badResponse,
        ),
      );
      final container = buildContainer(online: true, api: api);
      addTearDown(container.dispose);

      await expectLater(
        container.read(magazziniProvider.future),
        throwsA(isA<DioException>()),
      );
    });

    test('online the live answer wins, never merged with the mirror', () async {
      await seedMirror();
      final api = _FakeApiClient(magazzini: [_liveSede]);
      final container = buildContainer(online: true, api: api);
      addTearDown(container.dispose);

      final list = await container.read(magazziniProvider.future);

      expect(api.calls, 1);
      expect(list.single.id, 'live-w');
    });
  });

  group('furgoneDiUserProvider', () {
    test('offline resolves the technician\'s own van from the mirror', () async {
      await seedMirror();
      final api = _FakeApiClient(
        error: StateError('the network must not be touched offline'),
      );
      final container = buildContainer(online: false, api: api);
      addTearDown(container.dispose);

      final van = await container.read(furgoneDiUserProvider('u1').future);

      expect(api.calls, 0);
      expect(van?.id, 'w-van');
      expect(van?.isFurgone, isTrue);
    });

    test('offline a technician with no van gets null, not an error', () async {
      await seedMirror();
      final api = _FakeApiClient();
      final container = buildContainer(online: false, api: api);
      addTearDown(container.dispose);

      final van = await container.read(furgoneDiUserProvider('u2').future);

      expect(van, isNull);
      expect(api.calls, 0);
    });

    test('online the server assignment wins', () async {
      await seedMirror();
      const live = MagazzinoDto(
        id: 'live-van',
        nome: 'Furgone Bianchi',
        tipo: 'Furgone',
        assegnatoUserId: 'u1',
        isActive: true,
      );
      final api = _FakeApiClient(furgone: live);
      final container = buildContainer(online: true, api: api);
      addTearDown(container.dispose);

      final van = await container.read(furgoneDiUserProvider('u1').future);

      expect(api.calls, 1);
      expect(van?.id, 'live-van');
    });
  });
}
