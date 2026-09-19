import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/dictation/dictate_button.dart';
import 'package:tasktap_mobile/core/dictation/dictation_capability.dart';
import 'package:tasktap_mobile/core/dictation/dictation_service.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

/// Device capability is a prerequisite, established before any dictation UI exists (ADR-0017).
///
/// The trap this guards against is the ordinary one: build the voice UX, discover on the first
/// real handset that offline Italian is not there, and reach for the network transcriber to make
/// the feature "work" — quietly converting an offline-first capability into a network-dependent
/// one, which is the outcome the ADR exists to prevent.
///
/// So the rule is that dictation availability may never affect rapportino availability. If the
/// phone cannot do it, the technician has the same form and the same keyboard as before.
class _FakeDictation implements IDictationService {
  _FakeDictation(this._capability);

  final DictationCapability _capability;
  int starts = 0;
  bool stopped = false;

  @override
  Future<DictationCapability> capability() async => _capability;

  @override
  bool get isListening => false;

  @override
  Future<void> start({
    required ValueChanged<String> onTranscript,
    required VoidCallback onDone,
  }) async {
    starts++;
    onTranscript('sostituita la pompa di circolazione');
    onDone();
  }

  @override
  Future<void> stop() async => stopped = true;
}

const _ready = DictationCapability(
  recognizerAvailable: true,
  italianLocaleId: 'it_IT',
  onDeviceRecognitionAvailable: true,
  microphoneGranted: true,
);

void main() {
  group('capability is a result, not a boolean', () {
    test('everything present means dictation is offered', () {
      expect(_ready.canDictate, isTrue);
      expect(_ready.blocker, DictationBlocker.none);
      expect(_ready.unavailableMessage, isNull);
    });

    test('no recogniser at all', () {
      const capability = DictationCapability.unavailable();

      expect(capability.blocker, DictationBlocker.noRecognizer);
      expect(capability.canDictate, isFalse);
    });

    test('a recogniser that does not know Italian is not usable here', () {
      // Rapportini are written in Italian. An English-only recogniser is not a degraded
      // experience, it is the wrong one.
      const capability = DictationCapability(
        recognizerAvailable: true,
        italianLocaleId: null,
        onDeviceRecognitionAvailable: true,
        microphoneGranted: true,
      );

      expect(capability.blocker, DictationBlocker.noItalianLocale);
    });

    test('network-only recognition is a blocker, not a downgrade', () {
      // The whole decision in one assertion. A device that can only recognise via the network
      // gets no dictation at all, rather than dictation that ships site audio to a vendor and
      // stops working in the basement where it was most needed.
      const capability = DictationCapability(
        recognizerAvailable: true,
        italianLocaleId: 'it_IT',
        onDeviceRecognitionAvailable: false,
        microphoneGranted: true,
      );

      expect(capability.blocker, DictationBlocker.noOnDeviceRecognition);
      expect(capability.canDictate, isFalse);
    });

    test('a refused microphone is told apart from an incapable device', () {
      // Different message, different remedy. Collapsing both into "not supported" leaves the
      // technician with no idea that they can fix one of them.
      const capability = DictationCapability(
        recognizerAvailable: true,
        italianLocaleId: 'it_IT',
        onDeviceRecognitionAvailable: true,
        microphoneGranted: false,
      );

      expect(capability.blocker, DictationBlocker.microphoneDenied);
      expect(capability.unavailableMessage, contains('microfono'));
    });

    test('every blocker says something a technician can read', () {
      for (final blocker in DictationBlocker.values.where((b) => b != DictationBlocker.none)) {
        final capability = switch (blocker) {
          DictationBlocker.noRecognizer => const DictationCapability.unavailable(),
          DictationBlocker.noItalianLocale => const DictationCapability(
            recognizerAvailable: true,
            italianLocaleId: null,
            onDeviceRecognitionAvailable: true,
            microphoneGranted: true,
          ),
          DictationBlocker.noOnDeviceRecognition => const DictationCapability(
            recognizerAvailable: true,
            italianLocaleId: 'it_IT',
            onDeviceRecognitionAvailable: false,
            microphoneGranted: true,
          ),
          DictationBlocker.microphoneDenied => const DictationCapability(
            recognizerAvailable: true,
            italianLocaleId: 'it_IT',
            onDeviceRecognitionAvailable: true,
            microphoneGranted: false,
          ),
          DictationBlocker.none => _ready,
        };

        expect(capability.unavailableMessage, isNotNull, reason: '$blocker has no message');
        expect(capability.unavailableMessage, contains('Dettatura non disponibile'));
      }
    });
  });

  group('the affordance follows the capability', () {
    Future<_FakeDictation> pump(WidgetTester tester, DictationCapability capability) async {
      final fake = _FakeDictation(capability);
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [dictationServiceProvider.overrideWithValue(fake)],
          child: MaterialApp(
            home: Scaffold(
              body: DictateButton(controller: controller, onChanged: (_) {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return fake;
    }

    testWidgets('a capable device gets a microphone', (tester) async {
      await pump(tester, _ready);

      expect(find.byIcon(LucideIcons.mic), findsOneWidget);
    });

    testWidgets('an incapable device gets no working microphone', (tester) async {
      // Crossed-out, and it explains rather than doing nothing. A control that looks live and
      // then refuses is how a working app comes to feel unreliable.
      await pump(tester, const DictationCapability.unavailable());

      expect(find.byIcon(LucideIcons.mic), findsNothing);
      expect(find.byIcon(LucideIcons.micOff), findsOneWidget);
    });

    testWidgets('an incapable device never reaches the service', (tester) async {
      // The silent-network-fallback guard, at the UI layer.
      final fake = await pump(tester, const DictationCapability.unavailable());
      await tester.tap(find.byIcon(LucideIcons.micOff));
      await tester.pumpAndSettle();

      expect(fake.starts, 0);
    });

    testWidgets('the reason is available on demand', (tester) async {
      await pump(
        tester,
        const DictationCapability(
          recognizerAvailable: true,
          italianLocaleId: 'it_IT',
          onDeviceRecognitionAvailable: false,
          microphoneGranted: true,
        ),
      );

      await tester.tap(find.byIcon(LucideIcons.micOff));
      await tester.pumpAndSettle();

      expect(find.textContaining('offline'), findsOneWidget);
    });

    testWidgets('dictation appends to the field rather than replacing it', (tester) async {
      // Speaking must not discard what was already typed.
      final fake = _FakeDictation(_ready);
      final controller = TextEditingController(text: 'Intervento urgente.');
      addTearDown(controller.dispose);
      String? reported;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [dictationServiceProvider.overrideWithValue(fake)],
          child: MaterialApp(
            home: Scaffold(
              body: DictateButton(controller: controller, onChanged: (v) => reported = v),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(LucideIcons.mic));
      await tester.pumpAndSettle();

      expect(controller.text, 'Intervento urgente. sostituita la pompa di circolazione');
      expect(
        reported,
        controller.text,
        reason: 'the editor state, not the controller, is what reaches the draft row',
      );
    });
  });

  group('the readout answers the hardware question without a special build', () {
    // The remaining uncertainty in ADR-0017 is empirical: is offline Italian actually present on
    // the phones technicians carry? This is how that gets answered in ten seconds per handset,
    // and afterwards it is how a technician who cannot find the microphone gets told why.
    Future<void> pumpDiagnostics(WidgetTester tester, DictationCapability capability) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [dictationServiceProvider.overrideWithValue(_FakeDictation(capability))],
          child: MaterialApp(home: Scaffold(body: Consumer(builder: (context, ref, _) {
            final c = ref.watch(dictationCapabilityProvider);
            return c.when(
              loading: () => const Text('…'),
              error: (_, _) => const Text('errore'),
              data: (c) => Column(
                children: [
                  Text(c.canDictate ? 'Dettatura disponibile' : 'Dettatura non disponibile'),
                  Text('offline: ${c.onDeviceRecognitionAvailable}'),
                  if (!c.canDictate) Text(c.unavailableMessage!),
                ],
              ),
            );
          }))),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a capable handset reads as available', (tester) async {
      await pumpDiagnostics(tester, _ready);

      expect(find.text('Dettatura disponibile'), findsOneWidget);
      expect(find.text('offline: true'), findsOneWidget);
    });

    testWidgets('a network-only handset names offline as the missing piece', (tester) async {
      // The distinction that matters when reading a fleet: everything else can be green and the
      // answer still no.
      await pumpDiagnostics(
        tester,
        const DictationCapability(
          recognizerAvailable: true,
          italianLocaleId: 'it_IT',
          onDeviceRecognitionAvailable: false,
          microphoneGranted: true,
        ),
      );

      expect(find.text('Dettatura non disponibile'), findsOneWidget);
      expect(find.text('offline: false'), findsOneWidget);
      expect(find.textContaining('pacchetto vocale italiano'), findsOneWidget);
    });
  });
}
