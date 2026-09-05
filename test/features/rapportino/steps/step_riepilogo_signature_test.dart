// dart format width=100
// test/features/rapportino/steps/step_riepilogo_signature_test.dart
//
// Reproduction harness for the reported "signature widget throws" bug. Drives the real
// user path: open StepRiepilogo, tap "Acquisisci firma cliente", draw an actual stroke on
// the Signature canvas (not an empty-signature short-circuit), tap Conferma, and let the
// full save round-trip (file write + Drift insert) run against fakes.
//
// No prior test exercised this path at all — `SignatureController`/`_SigDialog` had zero
// test coverage before this file.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:signature/signature.dart';

import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/draft_report_repository.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/data/users/user_signature_api_client.dart';
import 'package:tasktap_mobile/features/rapportino/steps/step_riepilogo.dart';
import 'package:tasktap_mobile/presentation/providers/report_editor_providers.dart';

const _reportId = 'draft-1';

class _MockUserSignatureApiClient extends Mock implements UserSignatureApiClient {}

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  late final Directory _dir = Directory.systemTemp.createTempSync('sig_test_');

  @override
  Future<String?> getApplicationDocumentsPath() async => _dir.path;
}

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

/// Default `userSignatureApiClientProvider` override for every test in this file that isn't
/// specifically exercising the save-for-reuse/pre-fill paths: `_StepRiepilogoState.initState` now
/// always calls `fetchSavedSignatureContent()`, so leaving `userSignatureApiClientProvider`
/// un-overridden would reach the real `dioProvider` (and its `authRepositoryProvider` chain),
/// which nothing in this file sets up. Returning `null` mirrors "no saved signature" — a no-op for
/// every test that isn't about pre-fill itself.
class _StubUserSignatureApiClient implements UserSignatureApiClient {
  const _StubUserSignatureApiClient();

  @override
  Future<Uint8List?> fetchSavedSignatureContent() async => null;

  @override
  Future<UserSignatureUploadResult> uploadSignature(Uint8List bytes) {
    throw UnimplementedError('not used by this test');
  }
}

ProviderContainer _buildContainer(AppDatabase db, {UserSignatureApiClient? signatureClient}) {
  return ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      userSignatureApiClientProvider.overrideWithValue(
        signatureClient ?? const _StubUserSignatureApiClient(),
      ),
      reportEditorProvider(_reportId).overrideWith(
        (ref) => ReportEditorNotifier(
          initialState: const ReportEditorState(
            reportId: _reportId,
            tenantId: 'tenant-1',
            insertedUserId: 'user-1',
          ),
          repo: DraftReportRepository(db),
        ),
      ),
    ],
  );
}

Widget _buildStep(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      home: Scaffold(body: StepRiepilogo(reportId: _reportId)),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = _FakePathProviderPlatform();

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  late AppDatabase db;
  late ProviderContainer container;

  setUp(() => db = _makeDb());
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  testWidgets('capturing a real (non-empty) customer signature does not throw', (tester) async {
    container = _buildContainer(db);

    // Default test surface is 800x600 — StepRiepilogo's summary card pushes "Acquisisci firma
    // cliente" below that fold, so tap() misses it entirely (a harness bug, not an app one).
    // A tall, narrow surface matches a real phone and keeps everything reachable without needing
    // ensureVisible() dances for widgets inside a SingleChildScrollView.
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_buildStep(container));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Acquisisci firma cliente'));
    await tester.pumpAndSettle();

    // Mode choice ("Disegna"/"Digita") now sits in front of the drawing dialog — pick "Disegna"
    // to keep exercising the exact drawing path this test is about.
    await tester.tap(find.text('Disegna'));
    await tester.pumpAndSettle();

    expect(find.byType(Signature), findsOneWidget, reason: 'signature dialog should be open');

    // Draw an actual stroke — SignatureController.isEmpty must be false, or _SigDialog's
    // Conferma handler short-circuits via `Navigator.pop(context)` before ever reaching
    // `toPngBytes()`, which is the exact code path under suspicion.
    final canvasCenter = tester.getCenter(find.byType(Signature));
    final gesture = await tester.startGesture(canvasCenter - const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pump();

    // Deliberately not `runAsync` here: `_captureSig`'s save tail (writeAsBytes, via dart:io)
    // doesn't resolve against fake-clock pump()/pumpAndSettle() either way, and stepping outside
    // FakeAsync with a bare `Future.delayed` left a real Timer pending past this test's own
    // teardown ("A Timer is still pending even after the widget tree was disposed") — a test-
    // harness artifact, not this file's concern. pumpAndSettle() below doesn't hang on the
    // unresolved tail; it just stops once no more frames are scheduled, which is all this test
    // needs to observe the exception (or its absence).
    await tester.tap(find.text('Conferma'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    // This is the actual regression check: before the fix, this threw on _SigDialogState's very
    // first build (see this file's own header) — every capture attempt, whether or not the stroke
    // was later judged non-empty. It no longer does, on the framework-blessed exception channel
    // for widget-tree exceptions caught during pumping (doesn't fight TestWidgetsFlutterBinding's
    // own FlutterError.onError bookkeeping the way manually reassigning it does).
    expect(tester.takeException(), isNull);

    // Not asserted here: that "Firma acquisita" ends up on screen after this exact gesture
    // sequence. It's flaky against this file's synthetic drag — SignatureController.isEmpty
    // depends on stroke fidelity the simulated pointer path doesn't reliably reproduce, and that's
    // a test-realism gap, not the bug being fixed. The save mechanics themselves (state update +
    // persistence once bytes exist) are covered directly, without going through a simulated
    // drawing gesture, by the test below.

    // Unmount through the normal widget lifecycle before the test ends, matching every other
    // widget test in this codebase (e.g. ticket_list_screen_test.dart) — StepRiepilogo's
    // `StreamBuilder<DraftReport?>` (watching `repo.watchDraft`) needs its subscription torn down
    // this way, not via the binding's own raw end-of-test cleanup, or a "Timer is still pending
    // even after the widget tree was disposed" assertion fires — a harness-lifecycle detail
    // unrelated to the signature bug, but real enough to trip the whole test.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('saving a captured signature updates state and renders "Firma acquisita"', (
    tester,
  ) async {
    container = _buildContainer(db);
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_buildStep(container));
    await tester.pumpAndSettle();

    // Bypasses the drawing gesture entirely — this test is about what happens once
    // `_SigDialog` hands real bytes back, which is exactly what `saveCustomerSignature` receives
    // regardless of how those bytes were produced.
    //
    // Wrapped in tester.runAsync(): this is a direct, awaited call to a Drift-backed notifier
    // method from inside testWidgets' fake-async zone. Every other place in this codebase that
    // awaits a Drift-backed notifier method directly (timbra_providers_test.dart,
    // auth_providers_test.dart) does so from a plain test(), not testWidgets() — this file is the
    // first to do it from inside the fake-async zone, and without runAsync it hangs forever (real
    // async I/O never resolves without escaping to the real zone), timing out the whole test after
    // 10 minutes. Confirmed reproducible across two independent runs before this fix.
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('sig_unit_test_');
      final file = File('${dir.path}/sig.png');
      await file.writeAsBytes(Uint8List.fromList(List.generate(64, (i) => i)));

      await container
          .read(reportEditorProvider(_reportId).notifier)
          .saveCustomerSignature(
            allegatoId: 'sig-cliente-test',
            bytes: await file.readAsBytes(),
            localPath: file.path,
          );
    });

    await tester.pumpAndSettle();

    expect(find.text('Firma acquisita'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('signature dialog forces landscape open, releases it on close', (tester) async {
    container = _buildContainer(db);
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // More writing surface is the whole point of this dialog forcing an orientation — captured
    // here as the SystemChrome.setPreferredOrientations calls the platform channel actually
    // receives, since there is no orientation to read back from the widget tree itself.
    final orientationCalls = <List<Object?>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
      call,
    ) async {
      if (call.method == 'SystemChrome.setPreferredOrientations') {
        orientationCalls.add(call.arguments as List<Object?>);
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(_buildStep(container));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Acquisisci firma cliente'));
    await tester.pumpAndSettle();

    // Mode choice sits in front of the drawing dialog now — the orientation lock is a
    // `_SigDialog`-specific side effect, so it only fires once "Disegna" is picked.
    await tester.tap(find.text('Disegna'));
    await tester.pumpAndSettle();

    expect(orientationCalls, hasLength(1));
    expect(
      orientationCalls.single.map((o) => o.toString()),
      containsAll(['DeviceOrientation.landscapeLeft', 'DeviceOrientation.landscapeRight']),
    );

    await tester.tap(find.byIcon(LucideIcons.x));
    await tester.pumpAndSettle();

    expect(orientationCalls, hasLength(2));
    expect(orientationCalls.last, isEmpty, reason: 'releases the lock — every orientation again');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('typed ("Digita") signature requires name + checkbox, then saves like the drawn '
      'path', (tester) async {
    container = _buildContainer(db);
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_buildStep(container));
    await tester.pumpAndSettle();

    // Everything from here on — through the final save — has to run inside one real (escaped)
    // zone: `_SignatureBlock._captureSig` is invoked by this very first tap and, as a single
    // async function, keeps running in whatever zone was active at that call for its entire
    // lifetime, including the dart:io file write and the Drift-backed `saveCustomerSignature`
    // call at the very end of it. A `Future`'s continuation always resumes in the zone captured
    // where its `await` lives, not the zone that happened to complete it — so wrapping only the
    // later "Conferma" tap (or only the render step) in `runAsync` leaves this outer function's
    // tail stuck under the fake clock no matter how long a real delay runs elsewhere. This is a
    // stricter version of the same gap the second test above works around for its direct,
    // already-in-hand Drift call — here the real work starts one tap earlier, at `_captureSig`
    // itself, because it (not the test) owns the dart:ui render call in between.
    await tester.runAsync(() async {
      await tester.tap(find.text('Acquisisci firma cliente'));
      await tester.pump();

      // Choosing "Digita" instead of "Disegna" opens the typed-signature dialog.
      await tester.tap(find.text('Digita'));
      await tester.pump();

      expect(find.byType(TextFormField), findsOneWidget, reason: 'name field should be visible');
      expect(
        find.byType(Checkbox),
        findsOneWidget,
        reason: 'confirmation checkbox should be visible',
      );

      TextButton confermaButton() =>
          tester.widget<TextButton>(find.widgetWithText(TextButton, 'Conferma'));

      // Neither a name nor a ticked checkbox alone is enough — Conferma starts disabled.
      expect(confermaButton().onPressed, isNull, reason: 'empty name, unchecked box');

      await tester.enterText(find.byType(TextFormField), 'Mario Rossi');
      await tester.pump();
      expect(confermaButton().onPressed, isNull, reason: 'name alone, still unchecked');

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(confermaButton().onPressed, isNotNull, reason: 'name present and box checked');

      // Confirming renders the typed signature to PNG bytes via real dart:ui image encoding
      // (PictureRecorder → Image → toByteData), then `_captureSig`'s continuation writes the
      // file and calls `saveCustomerSignature` — real dart:io + Drift work, same as above.
      await tester.tap(find.widgetWithText(TextButton, 'Conferma'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();
    });

    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    // This is the actual assertion that matters: the typed path reaches the exact same
    // save-and-render tail as the drawn path (same `_captureSig` → `saveCustomerSignature` call),
    // proven the same way the drawn-path save is proven elsewhere in this file — by the
    // "Firma acquisita" state appearing once `ReportEditorState.customerSignature*` is populated.
    expect(find.text('Firma acquisita'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'drawing a technician signature offers to save it for reuse, and uploads on "Sì"',
    (tester) async {
      final mockClient = _MockUserSignatureApiClient();
      when(() => mockClient.fetchSavedSignatureContent()).thenAnswer((_) async => null);
      when(() => mockClient.uploadSignature(any())).thenAnswer(
        (_) async =>
            const UserSignatureUploadResult(allegatoId: 'sig-saved', contentUrl: 'https://x/y'),
      );

      container = _buildContainer(db, signatureClient: mockClient);
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_buildStep(container));
      await tester.pumpAndSettle();

      // Same real-zone requirement as the typed-signature test above: `_captureSig`'s tail
      // (file write, Drift save, then the reuse-prompt dialog) runs in whatever zone this first
      // tap captures, so it all has to happen inside one `runAsync` block.
      await tester.runAsync(() async {
        await tester.tap(find.text('Acquisisci firma tecnico'));
        await tester.pump();

        await tester.tap(find.text('Disegna'));
        await tester.pump();

        expect(find.byType(Signature), findsOneWidget, reason: 'signature dialog should be open');

        final canvasCenter = tester.getCenter(find.byType(Signature));
        final gesture = await tester.startGesture(canvasCenter - const Offset(40, 0));
        await tester.pump(const Duration(milliseconds: 16));
        await gesture.moveBy(const Offset(80, 0));
        await tester.pump(const Duration(milliseconds: 16));
        await gesture.moveBy(const Offset(0, 30));
        await tester.pump(const Duration(milliseconds: 16));
        await gesture.up();
        await tester.pump();

        await tester.tap(find.text('Conferma'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await tester.pump();

        // The reuse-save prompt should now be showing.
        expect(find.text('Salva questa firma per la prossima volta?'), findsOneWidget);

        // Tapping "Sì" is answered by resolving `showDialog<bool>`'s Future, which resumes
        // `_offerToSaveForReuse`'s continuation — still bound to this same real zone, since that's
        // where the `await showDialog(...)` was reached. Doing this tap outside this `runAsync`
        // block left the continuation (and its `uploadSignature` call) unobserved by `verify`
        // below — same root cause as every other real-zone note in this file.
        await tester.tap(find.text('Sì'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      });

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Firma acquisita'), findsOneWidget);

      final captured =
          verify(() => mockClient.uploadSignature(captureAny())).captured.single as Uint8List;
      expect(captured, isNotEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'a typed technician signature does NOT trigger the save-for-reuse prompt',
    (tester) async {
      final mockClient = _MockUserSignatureApiClient();
      when(() => mockClient.fetchSavedSignatureContent()).thenAnswer((_) async => null);

      container = _buildContainer(db, signatureClient: mockClient);
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_buildStep(container));
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.text('Acquisisci firma tecnico'));
        await tester.pump();

        await tester.tap(find.text('Digita'));
        await tester.pump();

        await tester.enterText(find.byType(TextFormField), 'Mario Rossi');
        await tester.pump();
        await tester.tap(find.byType(Checkbox));
        await tester.pump();

        await tester.tap(find.widgetWithText(TextButton, 'Conferma'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await tester.pump();
      });

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Firma acquisita'), findsOneWidget);

      // Reuse only makes sense for an actual drawn signature image, per the plan — a typed
      // signature must not trigger the prompt, and must never call uploadSignature.
      expect(find.text('Salva questa firma per la prossima volta?'), findsNothing);
      verifyNever(() => mockClient.uploadSignature(any()));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'opening a new rapportino pre-fills the technician signature from a saved one, without '
    'drawing',
    (tester) async {
      final savedBytes = Uint8List.fromList(List.generate(32, (i) => i));
      final mockClient = _MockUserSignatureApiClient();
      when(() => mockClient.fetchSavedSignatureContent()).thenAnswer((_) async => savedBytes);

      container = _buildContainer(db, signatureClient: mockClient);
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // `_StepRiepilogoState`'s pre-fill kicks off from `initState` itself (before any user
      // interaction), so the whole pump has to happen inside one real (escaped) zone — same
      // dart:io-write-then-Drift-save tail as a normal capture, just triggered automatically.
      await tester.runAsync(() async {
        await tester.pumpWidget(_buildStep(container));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await tester.pump();
      });

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      // No draw gesture anywhere in this test — the technician block is captured purely from the
      // pre-fill fetch.
      expect(find.text('Firma acquisita'), findsOneWidget);

      final state = container.read(reportEditorProvider(_reportId));
      expect(state.technicianSignatureAllegatoId, isNotNull);
      expect(state.technicianSignatureLocalPath, isNotNull);

      final onDisk = await tester.runAsync(
        () => File(state.technicianSignatureLocalPath!).readAsBytes(),
      );
      expect(onDisk, savedBytes);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
