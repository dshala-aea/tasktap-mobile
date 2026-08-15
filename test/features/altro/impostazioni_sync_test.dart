import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasktap_mobile/data/settings/notification_settings_api_client.dart';
import 'package:tasktap_mobile/domain/auth/i_auth_repository.dart';
import 'package:tasktap_mobile/features/altro/impostazioni_provider.dart';

class _MockAuthRepository extends Mock implements IAuthRepository {}

/// Records what was sent and answers with whatever the test wants.
class _FakeApi implements NotificationSettingsApiClient {
  _FakeApi({this.remote, this.failFetch = false, this.failUpdate = false});

  NotificationSettingsDto? remote;
  bool failFetch;
  bool failUpdate;

  int fetchCalls = 0;
  final List<Map<String, bool?>> updates = [];

  @override
  Future<NotificationSettingsDto> fetch() async {
    fetchCalls++;
    if (failFetch) throw DioException(requestOptions: RequestOptions(path: '/x'));
    return remote ??
        const NotificationSettingsDto(
          enablePush: true,
          ticketNotifications: true,
          documentNotifications: true,
        );
  }

  @override
  Future<void> update({
    bool? enablePush,
    bool? ticketNotifications,
    bool? documentNotifications,
  }) async {
    updates.add({
      'enablePush': enablePush,
      'ticketNotifications': ticketNotifications,
      'documentNotifications': documentNotifications,
    });
    if (failUpdate) throw DioException(requestOptions: RequestOptions(path: '/x'));
  }
}

const _kPending = 'settings.notifiche_pending';

void main() {
  late _MockAuthRepository repo;

  setUp(() {
    repo = _MockAuthRepository();
    when(() => repo.currentUser).thenReturn(null);
  });

  /// Builds the notifier and lets its constructor's load + reconcile settle.
  Future<ImpostazioniNotifier> build(_FakeApi api) async {
    final n = ImpostazioniNotifier(repo, api);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    return n;
  }

  group('reconcile direction', () {
    test('pulls the server values when nothing local is pending', () async {
      SharedPreferences.setMockInitialValues({'settings.notifiche_interventi': true});
      final api = _FakeApi(
        remote: const NotificationSettingsDto(
          enablePush: true,
          ticketNotifications: false,
          documentNotifications: true,
        ),
      );

      final n = await build(api);

      // A change made on the technician's other handset arrives here.
      expect(n.state.notificheInterventi, isFalse);
      expect(api.updates, isEmpty);
    });

    test('pushes instead of pulling when a local change never reached the server', () async {
      // The state a technician is left in after toggling something in a basement.
      SharedPreferences.setMockInitialValues({
        _kPending: true,
        'settings.notifiche_rapportini': false,
      });
      final api = _FakeApi(
        remote: const NotificationSettingsDto(
          enablePush: true,
          ticketNotifications: true,
          documentNotifications: true,
        ),
      );

      final n = await build(api);

      // Pulling here would drag the server's older `true` back over the technician's `false`, and
      // the setting would appear to undo itself minutes after they set it.
      expect(api.fetchCalls, 0);
      expect(api.updates.single['documentNotifications'], isFalse);
      expect(n.state.notificheRapportini, isFalse);
    });

    test('an unreachable server leaves local settings untouched', () async {
      SharedPreferences.setMockInitialValues({'settings.notifiche_interventi': false});
      final api = _FakeApi(failFetch: true);

      final n = await build(api);

      expect(n.state.notificheInterventi, isFalse);
    });
  });

  group('toggling', () {
    test('sends only the three server-backed settings', () async {
      SharedPreferences.setMockInitialValues({});
      final api = _FakeApi();
      final n = await build(api);
      api.updates.clear();

      n.toggle(key: 'notificheInterventi');
      await Future<void>.delayed(Duration.zero);

      // The other seven fields on UpdateSettingsRequest are left absent so the server keeps
      // whatever the office web app set; sending client defaults would reset them.
      expect(api.updates.single.keys, {
        'enablePush',
        'ticketNotifications',
        'documentNotifications',
      });
      expect(api.updates.single['ticketNotifications'], isFalse);
    });

    test('a device-only setting is never sent', () async {
      SharedPreferences.setMockInitialValues({});
      final api = _FakeApi();
      final n = await build(api);
      api.updates.clear();

      n.toggle(key: 'temaScuro');
      n.toggle(key: 'geoLocazione');
      n.toggle(key: 'syncOffline');
      n.toggle(key: 'autenticazioneBiometrica');
      await Future<void>.delayed(Duration.zero);

      // No server field corresponds to any of these. Sending them would be inventing a contract.
      expect(api.updates, isEmpty);
    });

    test('a failed send keeps the change and leaves it marked pending', () async {
      SharedPreferences.setMockInitialValues({});
      final api = _FakeApi(failUpdate: true);
      final n = await build(api);

      n.toggle(key: 'notificheRapportini');
      await Future<void>.delayed(Duration.zero);

      // Snapping the toggle back because a request timed out would be worse than syncing late.
      expect(n.state.notificheRapportini, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(_kPending), isTrue);
    });

    test('a successful send clears the pending mark', () async {
      SharedPreferences.setMockInitialValues({});
      final api = _FakeApi();
      final n = await build(api);

      n.toggle(key: 'notificheRapportini');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(_kPending), isFalse);
    });
  });

  group('NotificationSettingsDto', () {
    test('a field the server stops sending reads as on, not as switched off', () {
      final dto = NotificationSettingsDto.fromJson({});

      // Matches the server's own get-or-create defaults. Defaulting to false would silently
      // present every channel as disabled after a rename.
      expect(dto.enablePush, isTrue);
      expect(dto.ticketNotifications, isTrue);
      expect(dto.documentNotifications, isTrue);
    });
  });
}
