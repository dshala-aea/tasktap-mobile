import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasktap_mobile/data/settings/notification_settings_api_client.dart';
import 'package:tasktap_mobile/domain/auth/i_auth_repository.dart';
import 'package:tasktap_mobile/features/altro/impostazioni_provider.dart';

class _MockAuthRepository extends Mock implements IAuthRepository {}

const _defaultDto = NotificationSettingsDto(
  enableInApp: true,
  enablePush: true,
  enableEmail: true,
  ticketNotifications: true,
  scheduleNotifications: true,
  licenseNotifications: true,
  workLogNotifications: true,
  documentNotifications: true,
  mentionNotifications: true,
);

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
    return remote ?? _defaultDto;
  }

  @override
  Future<void> update({
    bool? enableInApp,
    bool? enablePush,
    bool? enableEmail,
    bool? ticketNotifications,
    bool? scheduleNotifications,
    bool? licenseNotifications,
    bool? workLogNotifications,
    bool? documentNotifications,
    bool? mentionNotifications,
  }) async {
    updates.add({
      'enableInApp': enableInApp,
      'enablePush': enablePush,
      'enableEmail': enableEmail,
      'ticketNotifications': ticketNotifications,
      'scheduleNotifications': scheduleNotifications,
      'licenseNotifications': licenseNotifications,
      'workLogNotifications': workLogNotifications,
      'documentNotifications': documentNotifications,
      'mentionNotifications': mentionNotifications,
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
          enableInApp: true,
          enablePush: true,
          enableEmail: true,
          ticketNotifications: false,
          scheduleNotifications: true,
          licenseNotifications: true,
          workLogNotifications: true,
          documentNotifications: true,
          mentionNotifications: true,
        ),
      );

      final n = await build(api);

      // A change made on the technician's other handset arrives here.
      expect(n.state.notificheInterventi, isFalse);
      expect(api.updates, isEmpty);
    });

    test('pulls all nine server-backed fields, not just the original three', () async {
      SharedPreferences.setMockInitialValues({});
      final api = _FakeApi(
        remote: const NotificationSettingsDto(
          enableInApp: false,
          enablePush: true,
          enableEmail: false,
          ticketNotifications: true,
          scheduleNotifications: false,
          licenseNotifications: false,
          workLogNotifications: false,
          documentNotifications: true,
          mentionNotifications: false,
        ),
      );

      final n = await build(api);

      expect(n.state.notificheInApp, isFalse);
      expect(n.state.notificheEmail, isFalse);
      expect(n.state.notifichePianificazione, isFalse);
      expect(n.state.notificheLicenza, isFalse);
      expect(n.state.notificheOrePresenze, isFalse);
      expect(n.state.notificheMenzioni, isFalse);
    });

    test('pushes instead of pulling when a local change never reached the server', () async {
      // The state a technician is left in after toggling something in a basement.
      SharedPreferences.setMockInitialValues({
        _kPending: true,
        'settings.notifiche_rapportini': false,
      });
      final api = _FakeApi(remote: _defaultDto);

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
    test('sends all nine server-backed settings', () async {
      SharedPreferences.setMockInitialValues({});
      final api = _FakeApi();
      final n = await build(api);
      api.updates.clear();

      n.toggle(key: 'notificheInterventi');
      await Future<void>.delayed(Duration.zero);

      // Every field except enableSMS (which has no toggle in this app) is present on every send —
      // the server only applies the one that actually changed, but the client always states its
      // full current view of the nine it owns.
      expect(api.updates.single.keys, {
        'enableInApp',
        'enablePush',
        'enableEmail',
        'ticketNotifications',
        'scheduleNotifications',
        'licenseNotifications',
        'workLogNotifications',
        'documentNotifications',
        'mentionNotifications',
      });
      expect(api.updates.single['ticketNotifications'], isFalse);
    });

    test('toggling a new category (Pianificazione) is reflected in the next send', () async {
      SharedPreferences.setMockInitialValues({});
      final api = _FakeApi();
      final n = await build(api);
      api.updates.clear();

      n.toggle(key: 'notifichePianificazione');
      await Future<void>.delayed(Duration.zero);

      expect(n.state.notifichePianificazione, isFalse);
      expect(api.updates.single['scheduleNotifications'], isFalse);
      // Untouched fields are still sent, but with their unchanged (still-true) value.
      expect(api.updates.single['ticketNotifications'], isTrue);
    });

    test('toggling Email/In-app/Licenza/Ore e presenze/Menzioni is server-backed', () async {
      SharedPreferences.setMockInitialValues({});
      final api = _FakeApi();
      final n = await build(api);

      for (final key in [
        'notificheEmail',
        'notificheInApp',
        'notificheLicenza',
        'notificheOrePresenze',
        'notificheMenzioni',
      ]) {
        api.updates.clear();
        n.toggle(key: key);
        await Future<void>.delayed(Duration.zero);
        expect(api.updates, isNotEmpty, reason: '$key should push to the server');
      }
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
      expect(dto.enableInApp, isTrue);
      expect(dto.enablePush, isTrue);
      expect(dto.enableEmail, isTrue);
      expect(dto.ticketNotifications, isTrue);
      expect(dto.scheduleNotifications, isTrue);
      expect(dto.licenseNotifications, isTrue);
      expect(dto.workLogNotifications, isTrue);
      expect(dto.documentNotifications, isTrue);
      expect(dto.mentionNotifications, isTrue);
    });

    test('round-trips all nine fields from a full JSON payload', () {
      final dto = NotificationSettingsDto.fromJson({
        'enableInApp': false,
        'enablePush': true,
        'enableEmail': false,
        'enableSMS': true, // present server-side, deliberately not modeled here.
        'ticketNotifications': false,
        'scheduleNotifications': true,
        'licenseNotifications': false,
        'workLogNotifications': true,
        'documentNotifications': false,
        'mentionNotifications': true,
      });

      expect(dto.enableInApp, isFalse);
      expect(dto.enablePush, isTrue);
      expect(dto.enableEmail, isFalse);
      expect(dto.ticketNotifications, isFalse);
      expect(dto.scheduleNotifications, isTrue);
      expect(dto.licenseNotifications, isFalse);
      expect(dto.workLogNotifications, isTrue);
      expect(dto.documentNotifications, isFalse);
      expect(dto.mentionNotifications, isTrue);
    });
  });
}
