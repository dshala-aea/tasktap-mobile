// test/features/ticket/ticket_detail_screen_test.dart
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/data/tickets/pending_ticket_attachment_repository.dart';
import 'package:tasktap_mobile/data/tickets/pending_ticket_attachment_state.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/domain/auth/i_auth_repository.dart';
import 'package:tasktap_mobile/features/ticket/ticket_detail_screen.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

/// Stands in for the platform camera/gallery — the same seam the plugin itself exists for; every
/// call is local capture + file read, never a platform channel a widget test can drive directly.
/// Returns [pathToReturn] as the "picked" file, or null to simulate the user backing out of the
/// picker.
class _FakeImagePickerPlatform extends ImagePickerPlatform {
  _FakeImagePickerPlatform(this.pathToReturn);

  final String? pathToReturn;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    final path = pathToReturn;
    return path == null ? null : XFile(path);
  }
}

class MockAuthRepository extends Mock implements IAuthRepository {}

class MockDio extends Mock implements Dio {}

// Helper: build a Dio Response for a given status code + data.
Response<T> _okResponse<T>(T data, String path) => Response<T>(
  data: data,
  statusCode: 200,
  requestOptions: RequestOptions(path: path),
);

Widget _buildDetail({
  required AppDatabase db,
  required MockAuthRepository repo,
  String ticketId = 'ticket-1',
  Dio? dio,
  // Defaults to offline so pre-existing tests below (which never stub the
  // fetch-on-demand tab endpoints) get the deterministic "offline" tab
  // content rather than depending on how an unstubbed MockDio call fails.
  bool isOnline = false,
}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      appDatabaseProvider.overrideWithValue(db),
      dioProvider.overrideWithValue(dio ?? MockDio()),
      isOnlineProvider.overrideWithValue(isOnline),
    ],
    child: MaterialApp(home: TicketDetailScreen(ticketId: ticketId)),
  );
}

void main() {
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    registerFallbackValue(RequestOptions(path: '/'));
    await initializeDateFormatting('it', null);
  });

  late AppDatabase db;
  late MockAuthRepository repo;
  late StreamController<AuthUser?> authStream;
  final ImagePickerPlatform originalImagePickerPlatform = ImagePickerPlatform.instance;
  final List<File> tempFiles = [];

  final fakeUser = AuthUser(
    id: 'u1',
    email: 'mario@tasktap.io',
    accessToken: 'token',
    refreshToken: 'refresh',
    expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = MockAuthRepository();
    authStream = StreamController<AuthUser?>.broadcast();
    when(() => repo.authStateChanges).thenAnswer((_) => authStream.stream);
    when(() => repo.currentUser).thenReturn(fakeUser);
  });

  tearDown(() async {
    authStream.close();
    await db.close();
    ImagePickerPlatform.instance = originalImagePickerPlatform;
    for (final f in tempFiles) {
      if (f.existsSync()) f.deleteSync();
    }
    tempFiles.clear();
  });

  /// A real file on disk — `_pickImage`'s size check reads it with `File.readAsBytes`, so the
  /// "picked" path has to resolve to something real, not a fixture string. Sparse (via
  /// `truncate`) rather than actually written: the 10 MB-cap test only needs the right *length*,
  /// and allocating/writing a real multi-megabyte buffer on every run is unnecessary I/O.
  File makeTempFile(String name, int sizeBytes) {
    // No prefix: `xfile.name` (what `_pickImage` uses as `fileName`) is derived from the path's
    // basename, so the file's own name has to be exactly what a test expects to find on screen.
    final file = File('${Directory.systemTemp.path}/$name');
    final raf = file.openSync(mode: FileMode.write);
    raf.truncateSync(sizeBytes);
    raf.closeSync();
    tempFiles.add(file);
    return file;
  }

  Future<void> pump(
    WidgetTester tester, {
    String ticketId = 'ticket-1',
    Dio? dio,
    bool isOnline = false,
    // False for a fixture with an open (still-running) worklog entry: that renders a LiveDot,
    // whose pulse repeats forever and never lets pumpAndSettle's frame-quiescence check succeed —
    // it would otherwise hang until the 10-minute timeout. A handful of bounded pumps gives every
    // async provider chain the same room to resolve without waiting for an animation that, by
    // design, never stops.
    bool settle = true,
  }) async {
    await tester.pumpWidget(
      _buildDetail(db: db, repo: repo, ticketId: ticketId, dio: dio, isOnline: isOnline),
    );
    await tester.pump();
    authStream.add(fakeUser);
    if (settle) {
      await tester.pumpAndSettle(const Duration(seconds: 2));
    } else {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
    }
  }

  Future<void> seedBase(AppDatabase db) async {
    await db
        .into(db.ticketStatuses)
        .insert(
          TicketStatusesCompanion.insert(id: const Value(1), tenantId: 'tenant-1', name: 'Aperto'),
        );
    await db
        .into(db.ticketTypes)
        .insert(
          TicketTypesCompanion.insert(id: const Value(1), tenantId: 'tenant-1', name: 'Assistenza'),
        );
    await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            id: 'cust-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            companyName: 'ACME Srl',
          ),
        );
    await db
        .into(db.locations)
        .insert(
          LocationsCompanion.insert(
            id: 'loc-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            customerId: 'cust-1',
            name: 'Sede Milano',
          ),
        );
    await db
        .into(db.tickets)
        .insert(
          TicketsCompanion.insert(
            id: 'ticket-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 6, 1, 9),
            title: 'Perdita idrica bagno',
            customerId: 'cust-1',
            locationId: 'loc-1',
            statusId: 1,
            typeId: 1,
            description: const Value('Acqua che perde dal tubo.'),
            assignedUserId: const Value('user-1'),
          ),
        );
  }

  group('TicketDetailScreen', () {
    testWidgets('shows empty-state when ticket not found', (tester) async {
      await pump(tester, ticketId: 'nonexistent');
      expect(find.byType(EmptyState), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('renders KeyVal rows for Cliente and Sede', (tester) async {
      await seedBase(db);
      await pump(tester);

      expect(find.text('ACME Srl'), findsOneWidget);
      expect(find.text('Sede Milano'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('renders resolved StatusPill', (tester) async {
      await seedBase(db);
      await pump(tester);

      expect(find.byType(StatusPill), findsOneWidget);
      expect(find.text('Aperto'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('renders a compartment grid with all eight section labels', (tester) async {
      await seedBase(db);
      // A taller surface, for the same reason the Pianificazioni test below already uses one: the
      // grid lives well down a CustomScrollView, slivers build lazily, and on the default 600dp
      // test window it sits below the fold. The assertion is that the screen renders eight
      // section labels, not that they fit in 600dp.
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      await pump(tester);

      expect(find.byType(GridView), findsOneWidget);
      expect(find.text('Dettagli'), findsOneWidget);
      expect(find.text('Report'), findsOneWidget);
      expect(find.text('Controllo'), findsOneWidget);
      expect(find.text('Allegati'), findsOneWidget);
      expect(find.text('Pianificazioni'), findsOneWidget);
      expect(find.text('Ore'), findsOneWidget);
      expect(find.text('Fabbisogno'), findsOneWidget);
      expect(find.text('Storico'), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('names the assigned technician instead of showing their id', (tester) async {
      await seedBase(db);
      await db
          .into(db.colleagues)
          .insert(ColleaguesCompanion.insert(id: 'user-1', displayName: 'Mario Rossi'));
      await pump(tester);

      expect(find.text('Mario Rossi'), findsOneWidget);
      expect(find.text('user-1'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('falls back to the id when the mirror does not know them', (tester) async {
      // A colleague who left, or a sync that has not landed. An unfamiliar id is still something
      // to read out over the phone; a blank is not.
      await seedBase(db);
      await pump(tester);

      expect(find.text('user-1'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('a ticket that already has an owner offers no self-assign', (tester) async {
      // seedBase assigns user-1. Offering "take this" for a ticket somebody already holds invites
      // a technician to quietly reassign work away from a colleague.
      await seedBase(db);
      await pump(tester);

      expect(find.text('Prendi in carico'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('an unowned ticket offers self-assign', (tester) async {
      await seedBase(db);
      await (db.update(db.tickets)..where((t) => t.id.equals('ticket-1'))).write(
        const TicketsCompanion(assignedUserId: Value(null)),
      );
      await pump(tester);

      expect(find.text('Prendi in carico'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('the status pill opens the status sheet', (tester) async {
      await seedBase(db);
      await pump(tester);

      // The pill was a label; it is a control now, so it has to answer a tap.
      await tester.tap(find.byType(StatusPill));
      await tester.pumpAndSettle();

      expect(find.text('Cambia stato'), findsOneWidget);
      // The ticket's current status is marked rather than merely listed, so a technician can see
      // what they are changing from.
      expect(find.text('Aperto'), findsWidgets);

      await tester.tapAt(const Offset(10, 10)); // dismiss
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('Pianificazioni tab shows schedules', (tester) async {
      await seedBase(db);
      await db
          .into(db.schedules)
          .insert(
            SchedulesCompanion.insert(
              id: 'sched-1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 6, 1),
              ticketId: const Value('ticket-1'),
              activityDate: DateTime.utc(2026, 7, 10),
              timeStartMinutes: 480,
              timeEndMinutes: 1020,
              userId: 'user-1',
              statusId: 1,
              locationId: 'loc-1',
              title: 'Sopralluogo',
              description: '',
            ),
          );

      await pump(tester);

      // Tap "Pianificazioni" tab (index 2).
      // Use a taller surface so the tab bar is not obscured by the bottom actions bar.
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      await tester.pump();
      await tester.ensureVisible(find.text('Pianificazioni'));
      await tester.tap(find.text('Pianificazioni'));
      await tester.pumpAndSettle();

      expect(find.text('Sopralluogo'), findsOneWidget);
      await tester.binding.setSurfaceSize(null); // reset
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('the bottom bar holds a single leading doing-action', (tester) async {
      // Was four equal buttons in two rows: Assegna / Cliente / Crea rapportino / Timbra cantiere,
      // about 130dp of permanent chrome with no rank between them. What a technician does on a
      // ticket is start the work and write it up — "Timbra cantiere" moved to CantiereDetailScreen
      // (reached from this ticket's own cantiere chip; see the chip tests below), so it no longer
      // shares the bottom bar with "Crea rapportino" at all.
      await seedBase(db);
      await pump(tester);

      expect(find.text('Crea rapportino'), findsOneWidget);
      expect(find.text('Timbra cantiere'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('assegna stays in the header; customer nav lives on the Cliente row', (
      tester,
    ) async {
      // Reachable, not prominent: a dispatcher action and a navigation link do not belong in the
      // same weight as the two things the person on site came here to do. "Scheda cliente" used
      // to be a second header icon whose only job was "go look at this customer" — the customer's
      // name is already sitting right there in the fact card, so that row is the tap target now
      // instead of a disconnected briefcase glyph, and the header carries one action, not two.
      await seedBase(db);
      await pump(tester);

      expect(find.bySemanticsLabel('Assegna'), findsOneWidget);
      expect(find.bySemanticsLabel('Scheda cliente'), findsNothing);
      expect(
        find.ancestor(of: find.text('ACME Srl'), matching: find.byType(AppTappable)),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows description card when description is present', (tester) async {
      await seedBase(db);
      await pump(tester);
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Dettagli'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dettagli'));
      await tester.pumpAndSettle();

      expect(find.text('Acqua che perde dal tubo.'), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  // "Timbra cantiere" moved off this screen into CantiereDetailScreen (reached via
  // AppRoutes.cantieriDetailPath); this chip is this ticket's only remaining trace of a cantiere
  // link, and its only job is "does this ticket have one, and if so what's it called".
  group('TicketDetailScreen — cantiere chip', () {
    Future<void> seedWithCantiere(AppDatabase db) async {
      await seedBase(db);
      await db
          .into(db.cantieri)
          .insert(
            CantieriCompanion.insert(
              id: 'cant-1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              name: 'Cantiere Nord',
            ),
          );
      await (db.update(db.tickets)..where((t) => t.id.equals('ticket-1'))).write(
        const TicketsCompanion(cantiereId: Value('cant-1')),
      );
    }

    testWidgets('shows a cantiere chip when the ticket has one linked', (tester) async {
      await seedWithCantiere(db);
      await pump(tester);

      expect(find.textContaining('Cantiere:'), findsOneWidget);
      expect(find.text('Cantiere: Cantiere Nord'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows no cantiere chip when the ticket has none linked', (tester) async {
      await seedBase(db);
      await pump(tester);

      expect(find.textContaining('Cantiere:'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  // Feature audit module #11, Gap D: a technician working a ticket tied to a contract had no way
  // to see that contract's info at all — contracts were only reachable via the admin-only
  // /altro/contratti route.
  group('TicketDetailScreen — contract summary (Gap D)', () {
    Future<void> seedWithContract(AppDatabase db) async {
      await seedBase(db);
      await (db.update(db.tickets)..where((t) => t.id.equals('ticket-1'))).write(
        const TicketsCompanion(contractId: Value('contr-1')),
      );
    }

    // KeyVal renders its label uppercase (see key_val.dart's `_labelStyle`/`_horizontal`), so
    // "Contratto"/"Scadenza"/"Condizioni" render on screen as "CONTRATTO"/"SCADENZA"/
    // "CONDIZIONI" — matching how every other KeyVal label in this file is asserted against its
    // *value*, never its own label text, except here where the label's mere presence/absence is
    // exactly what's under test.
    testWidgets('shows no Contratto row when the ticket has no contract', (tester) async {
      await seedBase(db);
      await pump(tester);

      expect(find.text('CONTRATTO'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows the linked contract\'s name, resolved live', (tester) async {
      await seedWithContract(db);
      final dio = MockDio();
      when(() => dio.get<Map<String, dynamic>>('/api/contracts/contr-1')).thenAnswer(
        (_) async => _okResponse({
          'id': 'contr-1',
          'name': 'Manutenzione annuale',
        }, '/api/contracts/contr-1'),
      );

      await pump(tester, dio: dio, isOnline: true);

      expect(find.text('CONTRATTO'), findsOneWidget);
      expect(find.text('Manutenzione annuale'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('tapping the row opens a read-only sheet with scadenza and condizioni', (
      tester,
    ) async {
      await seedWithContract(db);
      final dio = MockDio();
      when(() => dio.get<Map<String, dynamic>>('/api/contracts/contr-1')).thenAnswer(
        (_) async => _okResponse({
          'id': 'contr-1',
          'name': 'Manutenzione annuale',
          'endDate': '2026-12-31T00:00:00Z',
          'condizioni': 'Pagamento a 30gg',
        }, '/api/contracts/contr-1'),
      );

      await pump(tester, dio: dio, isOnline: true);
      await tester.tap(find.text('Manutenzione annuale'));
      await tester.pumpAndSettle();

      expect(find.text('SCADENZA'), findsOneWidget);
      expect(find.text('31/12/2026'), findsOneWidget);
      expect(find.text('CONDIZIONI'), findsOneWidget);
      expect(find.text('Pagamento a 30gg'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('says plainly it is offline instead of showing a broken row', (tester) async {
      await seedWithContract(db);

      await pump(tester, isOnline: false);

      expect(find.text('Caricamento…'), findsNothing);
      expect(find.text('CONTRATTO'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  // Feature audit module #13, Gap 6: mobile already syncs `Ticket.commessaId` locally but showed
  // it nowhere in the UI — this fills that gap the same way Gap D filled the contract row above.
  group('TicketDetailScreen — commessa (Gap 6)', () {
    Future<void> seedWithCommessa(AppDatabase db) async {
      await seedBase(db);
      await (db.update(db.tickets)..where((t) => t.id.equals('ticket-1'))).write(
        const TicketsCompanion(commessaId: Value('commessa-1')),
      );
    }

    testWidgets('shows no Commessa row when the ticket has no commessa', (tester) async {
      await seedBase(db);
      await pump(tester);

      expect(find.text('COMMESSA'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets("shows the linked commessa's codice, resolved live", (tester) async {
      await seedWithCommessa(db);
      final dio = MockDio();
      when(() => dio.get<Map<String, dynamic>>('/api/commesse/commessa-1')).thenAnswer(
        (_) async => _okResponse({
          'id': 'commessa-1',
          'codice': 'COM-001',
        }, '/api/commesse/commessa-1'),
      );

      await pump(tester, dio: dio, isOnline: true);

      expect(find.text('COMMESSA'), findsOneWidget);
      expect(find.text('COM-001'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('says plainly it is offline instead of showing a broken row', (tester) async {
      await seedWithCommessa(db);

      await pump(tester, isOnline: false);

      expect(find.text('Caricamento…'), findsNothing);
      expect(find.text('COMMESSA'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  // Taps a tab by its label. Uses a taller surface so the tab bar isn't
  // obscured by the bottom actions bar (mirrors the Pianificazioni test
  // above, which established the pattern for this screen).
  Future<void> tapTab(WidgetTester tester, String label) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    await tester.pump();
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  // Bounded pumps rather than pumpAndSettle: the upload buttons show an indeterminate
  // CircularProgressIndicator while `_busy`, which — like the worklog LiveDot above — never lets
  // pumpAndSettle's frame-quiescence check succeed. Mirrors this file's own `pump(..., settle:
  // false)` workaround for the identical class of problem.
  // `tester.pump` only advances Flutter's own frame clock — it never waits for a genuine
  // asynchronous gap (File.readAsBytes, Drift's own I/O) to resolve on the real event loop. The
  // tap itself has to run inside `runAsync` so the operations it kicks off (`_pickImage`) execute
  // in the real zone; pumping afterwards then picks up the resulting setState calls. Also stands
  // in for pumpAndSettle, which never converges here — like the worklog LiveDot above, the upload
  // buttons show an indeterminate CircularProgressIndicator while `_busy`.
  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump(); // apply setState(_busy = true)
    // `_pickImage` chains several genuine async hops (file read, Drift's own background-isolate
    // write, the mocked-but-real Dio Future) that a plain `tester.pump` never waits for — it only
    // advances Flutter's own frame clock. Alternating a real delay with a pump, inside `runAsync`,
    // gives each hop a real window to land and a frame to be picked up in.
    await tester.runAsync(() async {
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });
  }

  /// [resetAndDispose] for a test that tapped one of the upload buttons above: `pumpAndSettle`
  /// never converges while `_busy`'s CircularProgressIndicator is still showing (same reasoning
  /// as `tapAndSettle` itself), and in a slow sandbox a large file read can still be in flight
  /// after `tapAndSettle`'s own bounded window. Bounded pumps here rather than an unbounded
  /// `pumpAndSettle` avoid that hang regardless.
  Future<void> resetAndDisposeAfterUpload(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(null);
    await tester.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> resetAndDispose(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(null);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Report / Controllo / Allegati / Fabbisogno — none of these have a local
  // Drift mirror (unlike Pianificazioni), so each is fetched on demand and
  // must distinguish three outcomes: real data, a genuine empty list, and
  // "we couldn't check" (offline). See ticket_providers.dart.
  // ══════════════════════════════════════════════════════════════════════════
  group('TicketDetailScreen — Report tab (index 0)', () {
    testWidgets('shows rapportini returned by the backend', (tester) async {
      await seedBase(db);
      final dio = MockDio();
      when(
        () => dio.get<Map<String, dynamic>>(
          '/api/Reports',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => _okResponse({
          'items': [
            {
              'id': 'rep-1',
              'title': 'Sostituzione valvola',
              'stato': 1,
              'createdAt': '2026-07-01T10:00:00Z',
            },
          ],
          'page': 1,
          'pageSize': 100,
          'totalItems': 1,
          'totalPages': 1,
        }, '/api/Reports'),
      );

      await pump(tester, dio: dio, isOnline: true);
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();

      expect(find.text('Sostituzione valvola'), findsOneWidget);
      expect(find.text('Inviato'), findsOneWidget);
      await resetAndDispose(tester);
    });

    testWidgets('shows an honest empty state when there are no rapportini', (tester) async {
      await seedBase(db);
      final dio = MockDio();
      when(
        () => dio.get<Map<String, dynamic>>(
          '/api/Reports',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => _okResponse({
          'items': <dynamic>[],
          'page': 1,
          'pageSize': 100,
          'totalItems': 0,
          'totalPages': 0,
        }, '/api/Reports'),
      );

      await pump(tester, dio: dio, isOnline: true);
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();

      expect(find.text('Nessun rapportino'), findsOneWidget);
      expect(find.text('Non ci sono rapportini registrati per questo ticket.'), findsOneWidget);
      await resetAndDispose(tester);
    });

    testWidgets('says plainly it is offline instead of showing an empty list', (tester) async {
      await seedBase(db);

      await pump(tester, isOnline: false);
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();

      expect(find.text('Rapportini non disponibili offline'), findsOneWidget);
      // Never claims "nessun rapportino" — that would say "there is
      // nothing" when the truth is "we could not check".
      expect(find.text('Nessun rapportino'), findsNothing);
      await resetAndDispose(tester);
    });
  });

  group('TicketDetailScreen — Controllo tab (index 1)', () {
    final controlsJson = [
      {
        'id': 'grp-1',
        'name': 'Sezione A',
        'description': null,
        'sortOrder': 0,
        'subgroups': <dynamic>[],
        'controls': [
          {
            'id': 'tc-1',
            'templateControlId': 'tpl-1',
            'controlLineageId': 'lin-1',
            'label': 'Pressione OK',
            'description': null,
            'type': 0, // Checkbox
            'isRequired': true,
            'options': null,
            'valoreLimite': null,
            'sortOrder': 0,
            'status': 'Completed',
            'stringValue': null,
            'boolValue': true,
            'dateValue': null,
            'completedByReportId': null,
            'completedAt': null,
          },
        ],
      },
    ];

    testWidgets('shows the real checklist resolved from the template', (tester) async {
      await seedBase(db);
      final dio = MockDio();
      when(
        () => dio.get<List<dynamic>>('/api/tickets/ticket-1/controls'),
      ).thenAnswer((_) async => _okResponse(controlsJson, '/api/tickets/ticket-1/controls'));

      await pump(tester, dio: dio, isOnline: true);
      await tapTab(tester, 'Controllo');

      expect(find.text('Pressione OK'), findsOneWidget);
      expect(find.text('Sì'), findsOneWidget);
      await resetAndDispose(tester);
    });

    testWidgets('says honestly that no controls are planned, not "coming soon"', (tester) async {
      await seedBase(db);
      final dio = MockDio();
      when(
        () => dio.get<List<dynamic>>('/api/tickets/ticket-1/controls'),
      ).thenAnswer((_) async => _okResponse(<dynamic>[], '/api/tickets/ticket-1/controls'));

      await pump(tester, dio: dio, isOnline: true);
      await tapTab(tester, 'Controllo');

      expect(find.text('Nessun controllo previsto'), findsOneWidget);
      await resetAndDispose(tester);
    });

    testWidgets('says plainly it is offline instead of showing an empty list', (tester) async {
      await seedBase(db);

      await pump(tester, isOnline: false);
      await tapTab(tester, 'Controllo');

      expect(find.text('Controlli non disponibili offline'), findsOneWidget);
      expect(find.text('Nessun controllo previsto'), findsNothing);
      await resetAndDispose(tester);
    });
  });

  group('TicketDetailScreen — Allegati tab (index 3)', () {
    final attachmentsJson = [
      {
        'id': 'att-1',
        'fileName': 'foto1.jpg',
        'contentType': 'image/jpeg',
        'sizeBytes': 204800,
        'contentUrl': '/api/tickets/ticket-1/attachments/att-1/content',
        'uploadedByUserId': 'u1',
        'createdAt': '2026-07-01T09:00:00Z',
      },
    ];

    testWidgets('shows attachments uploaded to the ticket', (tester) async {
      await seedBase(db);
      final dio = MockDio();
      when(
        () => dio.get<List<dynamic>>('/api/Tickets/ticket-1/attachments'),
      ).thenAnswer((_) async => _okResponse(attachmentsJson, '/api/Tickets/ticket-1/attachments'));

      await pump(tester, dio: dio, isOnline: true);
      await tapTab(tester, 'Allegati');

      expect(find.text('foto1.jpg'), findsOneWidget);
      await resetAndDispose(tester);
    });

    // ── Tap to view (2026-08-30 attachment viewer) ────────────────────────

    testWidgets('tapping an image attachment pushes the fullscreen viewer', (tester) async {
      await seedBase(db);
      final dio = MockDio();
      when(
        () => dio.get<List<dynamic>>('/api/Tickets/ticket-1/attachments'),
      ).thenAnswer((_) async => _okResponse(attachmentsJson, '/api/Tickets/ticket-1/attachments'));
      // The image viewer fetches bytes through the same authenticated dio — contentUrl is a
      // path on our own API, not an external storage URL (see openAttachment's own doc comment).
      when(
        () => dio.get<List<int>>(
          '/api/tickets/ticket-1/attachments/att-1/content',
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => _okResponse<List<int>>(
          [1, 2, 3],
          '/api/tickets/ticket-1/attachments/att-1/content',
        ),
      );

      await pump(tester, dio: dio, isOnline: true);
      await tapTab(tester, 'Allegati');
      await tester.tap(find.text('foto1.jpg'));
      await tester.pumpAndSettle();

      // The pushed screen's AppBar repeats the filename as its title. Its own copy is the only
      // one still onstage — the Allegati tab's ListRow is now offstage under the pushed route
      // (still in the tree, per Navigator semantics, just not what find.text sees by default).
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.text('foto1.jpg'), findsOneWidget);
      expect(find.text('foto1.jpg', skipOffstage: false), findsNWidgets(2));
      await resetAndDispose(tester);
    });

    testWidgets('tapping a non-image attachment attempts a download, not the image viewer', (
      tester,
    ) async {
      final pdfAttachment = [
        {
          'id': 'att-2',
          'fileName': 'certificato.pdf',
          'contentType': 'application/pdf',
          'sizeBytes': 51200,
          'contentUrl': '/api/tickets/ticket-1/attachments/att-2/content',
          'uploadedByUserId': 'u1',
          'createdAt': '2026-07-01T09:00:00Z',
        },
      ];
      await seedBase(db);
      final dio = MockDio();
      when(
        () => dio.get<List<dynamic>>('/api/Tickets/ticket-1/attachments'),
      ).thenAnswer((_) async => _okResponse(pdfAttachment, '/api/Tickets/ticket-1/attachments'));
      // No stub for the content GET — a MockDio throws MissingStubError on an unstubbed call,
      // which openAttachment's catch-all turns into the download-failure SnackBar. That's still
      // the right assertion: it proves the non-image branch tried to fetch rather than opening
      // the image viewer, without needing a real OpenFilex/platform-channel round trip.
      when(
        () => dio.get<List<int>>(
          '/api/tickets/ticket-1/attachments/att-2/content',
          options: any(named: 'options'),
        ),
      ).thenThrow(Exception('boom'));

      await pump(tester, dio: dio, isOnline: true);
      await tapTab(tester, 'Allegati');
      await tester.tap(find.text('certificato.pdf'));
      await tester.pumpAndSettle();

      expect(find.byType(InteractiveViewer), findsNothing);
      expect(find.text('Impossibile scaricare il file.'), findsOneWidget);
      await resetAndDispose(tester);
    });

    testWidgets('shows an honest empty state when there are no attachments', (tester) async {
      await seedBase(db);
      final dio = MockDio();
      when(
        () => dio.get<List<dynamic>>('/api/Tickets/ticket-1/attachments'),
      ).thenAnswer((_) async => _okResponse(<dynamic>[], '/api/Tickets/ticket-1/attachments'));

      await pump(tester, dio: dio, isOnline: true);
      await tapTab(tester, 'Allegati');

      expect(find.text('Nessun allegato'), findsOneWidget);
      await resetAndDispose(tester);
    });

    testWidgets('says plainly it is offline instead of showing an empty list', (tester) async {
      await seedBase(db);

      await pump(tester, isOnline: false);
      await tapTab(tester, 'Allegati');

      expect(find.text('Allegati non disponibili offline'), findsOneWidget);
      expect(find.text('Nessun allegato'), findsNothing);
      await resetAndDispose(tester);
    });

    testWidgets('a successful upload while online adds the file to the list', (tester) async {
      await seedBase(db);
      var serverAttachments = <Map<String, dynamic>>[];
      final dio = MockDio();
      when(() => dio.get<List<dynamic>>('/api/Tickets/ticket-1/attachments')).thenAnswer(
        (_) async => _okResponse<List<dynamic>>(
          serverAttachments,
          '/api/Tickets/ticket-1/attachments',
        ),
      );
      when(
        () => dio.post<Map<String, dynamic>>(
          '/api/tickets/ticket-1/attachments',
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async {
        // Simulates the server now having the file — the next GET (triggered by the queue's
        // onUploaded invalidation) picks this up.
        serverAttachments = [
          {
            'id': 'att-new',
            'fileName': 'foto.jpg',
            'contentType': 'image/jpeg',
            'sizeBytes': 2048,
            'contentUrl': '/api/tickets/ticket-1/attachments/att-new/content',
            'uploadedByUserId': 'u1',
            'createdAt': '2026-07-05T09:00:00Z',
          },
        ];
        return _okResponse({
          'allegatoId': 'att-new',
          'contentUrl': '/api/tickets/ticket-1/attachments/att-new/content',
        }, '/api/tickets/ticket-1/attachments');
      });

      ImagePickerPlatform.instance = _FakeImagePickerPlatform(
        makeTempFile('foto.jpg', 2048).path,
      );

      await pump(tester, dio: dio, isOnline: true);
      await tapTab(tester, 'Allegati');

      expect(find.text('Nessun allegato'), findsOneWidget);

      await tapAndSettle(tester, find.text('Fotocamera'));

      expect(find.text('foto.jpg'), findsOneWidget);
      expect(find.text('Nessun allegato'), findsNothing);
      await resetAndDisposeAfterUpload(tester);
    });

    testWidgets(
      'picking a photo while offline queues it locally without ever calling the network',
      (tester) async {
        // Exercises the real _pickImage → TicketAttachmentUploadQueue.upload(isOnline: false)
        // path end to end (queue-level offline/online branching itself is covered exhaustively in
        // ticket_attachment_upload_queue_test.dart). A MockDio with zero stubs makes the
        // assertion self-checking: any accidental network call throws instead of silently
        // succeeding.
        await seedBase(db);
        ImagePickerPlatform.instance = _FakeImagePickerPlatform(
          makeTempFile('offline.jpg', 4096).path,
        );

        final dio = MockDio();
        await pump(tester, dio: dio, isOnline: false);
        await tapTab(tester, 'Allegati');

        await tapAndSettle(tester, find.text('Galleria'));

        // A direct Drift read here (rather than through a watched provider a widget rebuild
        // would pick up) still needs `runAsync` — same reasoning as `tapAndSettle` itself.
        final rows = await tester.runAsync(
          () => PendingTicketAttachmentRepository(db).watchForTicket('ticket-1').first,
        );
        expect(rows, hasLength(1));
        expect(rows!.single.fileName, 'offline.jpg');
        expect(rows.single.state, 'pendingSync');
        verifyNever(
          () => dio.post<Map<String, dynamic>>(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          ),
        );
        await resetAndDisposeAfterUpload(tester);
      },
    );

    testWidgets(
      'a queued (pendingSync) attachment renders like the ticket list\'s own pending section',
      (tester) async {
        // Pure rendering check, seeded directly — the pendingSync row itself (and how it gets
        // there) is covered by the test above and by TicketAttachmentUploadQueue's own tests.
        // This is the "In attesa di connessione" read a technician actually sees, mirroring
        // _PendingTicketRow on the ticket list (see ticket_list_screen.dart).
        await seedBase(db);
        await PendingTicketAttachmentRepository(db).insert(
          id: 'pa-queued',
          ticketId: 'ticket-1',
          localPath: '/tmp/whatever.jpg',
          fileName: 'offline.jpg',
          contentType: 'image/jpeg',
          sizeBytes: 4096,
          state: PendingTicketAttachmentState.pendingSync,
        );

        await pump(tester, isOnline: false);
        await tapTab(tester, 'Allegati');

        expect(find.text('In sospeso (1)'), findsOneWidget);
        expect(find.text('offline.jpg'), findsOneWidget);
        expect(find.textContaining('In attesa di connessione'), findsOneWidget);
        await resetAndDispose(tester);
      },
    );

    testWidgets('a failed pending attachment offers Riprova, matching the retry pattern', (
      tester,
    ) async {
      await seedBase(db);
      final repo = PendingTicketAttachmentRepository(db);
      await repo.insert(
        id: 'pa-1',
        ticketId: 'ticket-1',
        localPath: '/tmp/whatever.jpg',
        fileName: 'whatever.jpg',
        contentType: 'image/jpeg',
        sizeBytes: 1024,
        state: PendingTicketAttachmentState.failed,
      );
      await repo.updateState(
        id: 'pa-1',
        state: PendingTicketAttachmentState.failed,
        error: 'Nessuna connessione. Riprova quando torni online.',
      );

      await pump(tester, isOnline: false);
      await tapTab(tester, 'Allegati');

      expect(find.textContaining('Caricamento non riuscito'), findsOneWidget);
      expect(find.text('Riprova'), findsOneWidget);
      await resetAndDispose(tester);
    });

    testWidgets('a file over the 10 MB cap is rejected client-side, never queued', (tester) async {
      await seedBase(db);
      final bigFile = makeTempFile('big.jpg', 10 * 1024 * 1024 + 1);
      ImagePickerPlatform.instance = _FakeImagePickerPlatform(bigFile.path);

      final dio = MockDio();
      when(
        () => dio.get<List<dynamic>>('/api/Tickets/ticket-1/attachments'),
      ).thenAnswer((_) async => _okResponse(<dynamic>[], '/api/Tickets/ticket-1/attachments'));

      await pump(tester, dio: dio, isOnline: true);
      await tapTab(tester, 'Allegati');

      await tapAndSettle(tester, find.text('Fotocamera'));

      expect(find.textContaining('10 MB'), findsOneWidget);
      expect(find.text('In sospeso (1)'), findsNothing);
      expect(find.text('big.jpg'), findsNothing);

      final rows = await tester.runAsync(
        () => PendingTicketAttachmentRepository(db).watchForTicket('ticket-1').first,
      );
      expect(rows, isEmpty);
      await resetAndDisposeAfterUpload(tester);
    });
  });

  group('TicketDetailScreen — Fabbisogno tab (index 4)', () {
    final materialiJson = [
      {
        'id': 'm-1',
        'materialeId': 'mat-1',
        'codice': 'ART001',
        'nome': 'Valvola idraulica',
        'quantita': 2,
        'unitaMisura': 'pz',
        'note': null,
        'disponibile': true,
      },
    ];

    testWidgets('shows materials planned for the ticket', (tester) async {
      await seedBase(db);
      final dio = MockDio();
      when(
        () => dio.get<List<dynamic>>('/api/Tickets/ticket-1/materiali'),
      ).thenAnswer((_) async => _okResponse(materialiJson, '/api/Tickets/ticket-1/materiali'));

      await pump(tester, dio: dio, isOnline: true);
      await tapTab(tester, 'Fabbisogno');

      expect(find.text('Valvola idraulica'), findsOneWidget);
      await resetAndDispose(tester);
    });

    testWidgets('shows an honest empty state when nothing is planned', (tester) async {
      await seedBase(db);
      final dio = MockDio();
      when(
        () => dio.get<List<dynamic>>('/api/Tickets/ticket-1/materiali'),
      ).thenAnswer((_) async => _okResponse(<dynamic>[], '/api/Tickets/ticket-1/materiali'));

      await pump(tester, dio: dio, isOnline: true);
      await tapTab(tester, 'Fabbisogno');

      expect(find.text('Nessun fabbisogno'), findsOneWidget);
      await resetAndDispose(tester);
    });

    testWidgets('says plainly it is offline instead of showing an empty list', (tester) async {
      await seedBase(db);

      await pump(tester, isOnline: false);
      await tapTab(tester, 'Fabbisogno');

      expect(find.text('Fabbisogno non disponibile offline'), findsOneWidget);
      expect(find.text('Nessun fabbisogno'), findsNothing);
      await resetAndDispose(tester);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Ore (index 5) and Storico (index 6). Both read through to the server —
  // neither has a Drift mirror — so both are stubbed on a MockDio.
  // ══════════════════════════════════════════════════════════════════════════

  /// Ore and Storico are the sixth and seventh tabs. At the 800dp width `tapTab` uses, the strip
  /// scrolls horizontally and a tap on the right-most labels lands on whatever is under them, so
  /// these two groups widen the surface enough for all seven to be laid out at once.
  Future<void> tapWideTab(WidgetTester tester, String label, {bool settle = true}) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1200));
    await tester.pump();
    await tester.ensureVisible(find.text(label));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.tap(find.text(label));
    // See `pump`'s own `settle` doc comment — a running worklog mounts a LiveDot whose pulse never
    // lets pumpAndSettle's quiescence check succeed.
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
    }
  }

  group('TicketDetailScreen — Ore tab (index 5)', () {
    MockDio dioWithWorklogs(List<Map<String, dynamic>> entries) {
      final dio = MockDio();
      when(() => dio.get<List<dynamic>>('/api/tickets/ticket-1/worklogs')).thenAnswer(
        (_) async => _okResponse<List<dynamic>>(entries, '/api/tickets/ticket-1/worklogs'),
      );
      return dio;
    }

    testWidgets('totals only the closed entries', (tester) async {
      await seedBase(db);
      final dio = dioWithWorklogs([
        {
          'id': 'w1',
          'ticketId': 'ticket-1',
          'userId': 'u1',
          'workDate': '2026-07-01T00:00:00Z',
          'startTime': '08:00:00',
          'endTime': '10:30:00',
          'isManualEntry': false,
        },
        {
          'id': 'w2',
          'ticketId': 'ticket-1',
          'userId': 'u1',
          'workDate': '2026-07-02T00:00:00Z',
          'startTime': '09:00:00',
          'endTime': '10:00:00',
          'isManualEntry': true,
        },
        {
          'id': 'w3',
          'ticketId': 'ticket-1',
          'userId': 'u1',
          'workDate': '2026-07-03T00:00:00Z',
          'startTime': '09:00:00',
          'endTime': null,
          'isManualEntry': false,
        },
      ]);

      await pump(tester, dio: dio, isOnline: true, settle: false);
      await tapWideTab(tester, 'Ore', settle: false);

      // 2:30 + 1:00 from the two closed entries. Deliberately a sum no single row also shows, so
      // the assertion cannot pass by matching a row's own duration.
      expect(find.text('3:30'), findsOneWidget);
      expect(find.textContaining('non è incluso nel totale'), findsOneWidget);
      // The open entry names itself as still running rather than reporting a duration. Asserting
      // on the row's subtitle, not on its '—' meta: the Chiusura KeyVal above renders a dash too,
      // so that finder matches two unrelated things.
      expect(find.textContaining('→ in corso'), findsOneWidget);
      await resetAndDispose(tester);
    });

    testWidgets('says honestly when nothing has been booked', (tester) async {
      await seedBase(db);
      await pump(tester, dio: dioWithWorklogs([]), isOnline: true);
      await tapWideTab(tester, 'Ore');

      expect(find.text('Nessuna ora registrata'), findsOneWidget);
      await resetAndDispose(tester);
    });

    testWidgets('says plainly it is offline instead of showing an empty list', (tester) async {
      await seedBase(db);
      await pump(tester, isOnline: false);
      await tapWideTab(tester, 'Ore');

      expect(find.text('Ore non disponibili offline'), findsOneWidget);
      await resetAndDispose(tester);
    });
  });

  group('TicketDetailScreen — Storico tab (index 6)', () {
    testWidgets('renders a status change by name, not by raw id', (tester) async {
      await seedBase(db);
      final dio = MockDio();
      when(() => dio.get<List<dynamic>>('/api/Tickets/ticket-1/history')).thenAnswer(
        (_) async => _okResponse<List<dynamic>>([
          {
            'id': 'h1',
            'ticketId': 'ticket-1',
            'fieldName': 'StatusId',
            'oldValue': null,
            'newValue': '1',
            'changedByUserId': 'u1',
            'changedAt': '2026-07-01T10:00:00Z',
          },
        ], '/api/Tickets/ticket-1/history'),
      );

      await pump(tester, dio: dio, isOnline: true);
      await tapWideTab(tester, 'Storico');

      // The audit table stores column names and raw values. Showing "StatusId: → 1" would put
      // database identifiers in front of a technician.
      expect(find.text('Stato'), findsOneWidget);
      expect(find.text('— → Aperto'), findsOneWidget);
      await resetAndDispose(tester);
    });

    testWidgets('keeps an untranslated field rather than dropping the change', (tester) async {
      await seedBase(db);
      final dio = MockDio();
      when(() => dio.get<List<dynamic>>('/api/Tickets/ticket-1/history')).thenAnswer(
        (_) async => _okResponse<List<dynamic>>([
          {
            'id': 'h1',
            'ticketId': 'ticket-1',
            'fieldName': 'SomeFutureColumn',
            'oldValue': 'a',
            'newValue': 'b',
            'changedByUserId': 'u1',
            'changedAt': '2026-07-01T10:00:00Z',
          },
        ], '/api/Tickets/ticket-1/history'),
      );

      await pump(tester, dio: dio, isOnline: true);
      await tapWideTab(tester, 'Storico');

      // A change nobody has a label for still happened; hiding it would make the trail lie.
      expect(find.text('SomeFutureColumn'), findsOneWidget);
      expect(find.text('a → b'), findsOneWidget);
      await resetAndDispose(tester);
    });

    testWidgets('says plainly it is offline instead of showing an empty list', (tester) async {
      await seedBase(db);
      await pump(tester, isOnline: false);
      await tapWideTab(tester, 'Storico');

      expect(find.text('Storico non disponibile offline'), findsOneWidget);
      await resetAndDispose(tester);
    });
  });
}
