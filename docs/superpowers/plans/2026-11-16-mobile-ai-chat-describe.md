# Mobile AI chat — fase Descrivi Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** La fase Descrivi del copilot mobile diventa un thread chat (operatore/assistente) con una striscia di completamento persistente; revisione e firma restano invariate.

**Architecture:** Il server fornisce già i turni (`GET /ai/conversations/{id}`) e il draft aggiornato a ogni turno. Si aggiungono tre unità pure/testabili — modello messaggi, modello di completamento, widget thread/striscia — e si ricabla `ai_copilot_screen.dart`: niente più auto-avanzamento a Controlla, CTA esplicita sempre attiva.

**Tech Stack:** Flutter/Dart, Riverpod, widget test con `flutter test`.

**Spec:** `docs/superpowers/specs/2026-11-16-mobile-ai-chat-describe-design.md`

## Global Constraints

- ADR-0023: la registrazione è l'input del modello, nessun ASR; non toccare upload/turni audio.
- Confirm risolve e non crea; la Firma resta una route sull'id locale scritto da Conferma.
- Nessun PII nuovo nei payload.
- Il gate reale resta `CanInvia` lato server: la striscia è indicativa, non un guard.
- `Controlla` sempre abilitato (quando esiste una sessione), anche con voci mancanti.
- Materiali soddisfatti da righe **o** `materialiNotRequired`.
- Motion ridotto rispettato; target ≥44 dp.
- **Verifica locale:** il SDK Flutter di questa macchina è più vecchio del vincolo `^3.13.0` e `flutter test` locale è vietato (OOM). Le verifiche si fanno con `flutter analyze`/`flutter test` **via CI** sul repo pubblico: push del branch e lettura del job. Ogni step di verifica qui sotto vale anche come "push e controlla CI" quando il comando locale non è eseguibile.

## Review Focus

- Ripresa di una sessione con turni: il thread deve mostrare TUTTI i turni nell'ordine del server, con i turni voce marcati — non solo l'ultima risposta.
- Turno fallito: il messaggio operatore non inviato deve restare visibile e riprova­bile, senza duplicarlo al retry riuscito.
- Materiali assenti con "nessun materiale utilizzato" attivo: la voce deve leggersi completa, non mancante.
- Ticket senza controlli: la voce Controlli non deve segnalare "manca" (non applicabile).
- Controlla con voci mancanti: deve restare tappabile e portare alla revisione, non bloccarsi.

---

### Task 1: `materialiNotRequired` sul draft + modello messaggi

**Files:**
- Modify: `lib/data/ai/ai_api_client.dart` (`AiCopilotDraftDto`, ctor + `fromJson`)
- Create: `lib/features/rapportino/ai_chat/chat_message.dart`
- Test: `test/features/rapportino/ai_chat/chat_message_test.dart`

**Interfaces:**
- Consumes: `AiConversationTurn {turnId, role, text, source, at}`, `AiTurnSource {typed, voice}` (esistenti).
- Produces:
  - `AiCopilotDraftDto.materialiNotRequired` (`bool`, default `false`).
  - `enum ChatRole { operator, assistant }`, `enum ChatSource { typed, voice }`
  - `class ChatMessage { const ChatMessage({required this.id, required this.role, required this.text, this.source = ChatSource.typed, this.at}); final String id; final ChatRole role; final String text; final ChatSource source; final DateTime? at; }`
  - `static List<ChatMessage> ChatMessage.fromTurns(List<AiConversationTurn> turns)`
  - `static ChatMessage ChatMessage.operatorVoice({required String id, DateTime? at})` → `text: 'Messaggio vocale'`, `source: voice`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/rapportino/ai_chat/chat_message_test.dart
test('fromTurns keeps server order and marks voice turns', () {
  final turns = [
    AiConversationTurn(turnId: 't1', role: 'Operator', text: 'Ho sostituito la valvola',
        source: AiTurnSource.typed, at: DateTime.utc(2026, 11, 16, 9)),
    AiConversationTurn(turnId: 't2', role: 'Assistant', text: 'Quanti materiali?',
        source: AiTurnSource.typed),
    AiConversationTurn(turnId: 't3', role: 'Operator', text: 'Nessuno',
        source: AiTurnSource.voice),
  ];
  final msgs = ChatMessage.fromTurns(turns);
  expect(msgs.map((m) => m.text), ['Ho sostituito la valvola', 'Quanti materiali?', 'Nessuno']);
  expect(msgs.map((m) => m.role), [ChatRole.operator, ChatRole.assistant, ChatRole.operator]);
  expect(msgs[2].source, ChatSource.voice);
});

test('draft parses materialiNotRequired, default false', () {
  expect(AiCopilotDraftDto.fromJson(const {}).materialiNotRequired, isFalse);
  expect(AiCopilotDraftDto.fromJson(const {'materialiNotRequired': true}).materialiNotRequired, isTrue);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/rapportino/ai_chat/chat_message_test.dart` (o CI). Expected: FAIL — `ChatMessage` undefined.

- [ ] **Step 3: Implement**

Aggiungere a `AiCopilotDraftDto`: `final bool materialiNotRequired;` (ctor `this.materialiNotRequired = false`), `materialiNotRequired: json['materialiNotRequired'] as bool? ?? false` in `fromJson`; `empty` resta valido.

`chat_message.dart`: enums e classe come sopra; `fromTurns` mappa `role == 'Operator'` → operator, altrimenti assistant; `source == AiTurnSource.voice` → voice; `id = turnId`.

- [ ] **Step 4: Run test to verify it passes** — expected PASS.
- [ ] **Step 5: Commit** `feat(ai): chat message model and the draft's materialiNotRequired flag`

---

### Task 2: regole di completamento

**Files:**
- Create: `lib/features/rapportino/ai_chat/completion.dart`
- Test: `test/features/rapportino/ai_chat/completion_test.dart`

**Interfaces:**
- Consumes: `AiCopilotDraftDto` (Task 1).
- Produces:
  - `enum CompletionState { complete, missing, notApplicable }`
  - `class CompletionItem { final String key; final CompletionState state; }` (`key` ∈ `tecnici|materiali|controlli|descrizione`)
  - `class AiChatCompletion { final List<CompletionItem> items; final bool readyForReview; final List<String> missingLabels; static AiChatCompletion fromDraft(AiCopilotDraftDto d); }`

- [ ] **Step 1: Write the failing test**

```dart
test('required rules: tecnici and materiali decide readiness', () {
  final empty = AiChatCompletion.fromDraft(AiCopilotDraftDto.empty);
  expect(empty.readyForReview, isFalse);
  expect(empty.missingLabels, ['tecnici', 'materiali']);

  final withFlag = AiChatCompletion.fromDraft(AiCopilotDraftDto.empty.copyWith(materialiNotRequired: true));
  expect(withFlag.items.firstWhere((i) => i.key == 'materiali').state, CompletionState.complete);
  expect(withFlag.readyForReview, isFalse); // tecnici still missing
});

test('controlli is notApplicable when the ticket has none', () {
  final c = AiChatCompletion.fromDraft(AiCopilotDraftDto.empty);
  expect(c.items.firstWhere((i) => i.key == 'controlli').state, CompletionState.notApplicable);
});

test('descrizione satisfied by activities or diagnosi/soluzione', () {
  final d = AiCopilotDraftDto.empty.copyWith(diagnosi: 'Valvola bloccata');
  expect(AiChatCompletion.fromDraft(d).items.firstWhere((i) => i.key == 'descrizione').state,
      CompletionState.complete);
});
```

(`copyWith` va aggiunto ad `AiCopilotDraftDto` in questo task: deve copiare TUTTI i campi esistenti — `diagnosi`, `soluzione`, `customerSignoffText`, `workers`, `materials`, `controlli`, `strumenti`, `activities`, `openItems` — più `materialiNotRequired`. `AiDraftWorkerRef` si costruisce con `AiDraftWorkerRef(userId:, fullName:, state: AiResolutionState.resolvedBySystem, hours: 2)`.)

- [ ] **Step 2: Run test — FAIL** (undefined).
- [ ] **Step 3: Implement** le regole della spec: tecnici = `workers.isNotEmpty`; materiali = `materials.isNotEmpty || materialiNotRequired`; controlli = `controlli.isEmpty ? notApplicable : complete`; descrizione = `activities.isNotEmpty || diagnosi/soluzione non vuoti`; `readyForReview = tecnici && materiali`; `missingLabels` solo le chiavi `missing`, in ordine `tecnici, materiali`.
- [ ] **Step 4: Run test — PASS.**
- [ ] **Step 5: Commit** `feat(ai): completion rules for the chat's status strip`

---

### Task 3: striscia di completamento

**Files:**
- Create: `lib/features/rapportino/ai_chat/ai_completion_strip.dart`
- Test: `test/features/rapportino/ai_chat/ai_completion_strip_test.dart`

**Interfaces:**
- Consumes: `AiChatCompletion` (Task 2).
- Produces: `class AiCompletionStrip extends StatelessWidget { const AiCompletionStrip({super.key, required this.completion}); final AiChatCompletion completion; }`
  Keys: `ValueKey('ai-completion-tecnici'|'materiali'|'controlli'|'descrizione')`, `ValueKey('ai-completion-summary')`.

- [ ] **Step 1: Write the failing test**

```dart
testWidgets('summary says ready when required items are complete', (tester) async {
  final c = AiChatCompletion.fromDraft(AiCopilotDraftDto.empty.copyWith(
    materialiNotRequired: true,
    workers: [AiDraftWorkerRef(userId: 'u1', fullName: 'Mario', hours: 2, state: AiResolutionState.resolvedBySystem)],
  ));
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: AiCompletionStrip(completion: c))));
  expect(find.byKey(const ValueKey('ai-completion-summary')), findsOneWidget);
  expect(find.text('Pronto per la revisione'), findsOneWidget);
});

testWidgets('summary names what is missing', (tester) async {
  final c = AiChatCompletion.fromDraft(AiCopilotDraftDto.empty);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: AiCompletionStrip(completion: c))));
  expect(find.text('Manca: tecnici, materiali'), findsOneWidget);
});
```

- [ ] **Step 2: Run — FAIL.**
- [ ] **Step 3: Implement** chip (icona ✓/!/○ + label) e riga di sintesi; `notApplicable` → chip grigia "se previsti"; usa i token esistenti (`context.colors`, `AppSpacing`, `AiCard`/`AiLabel` se adatti).
- [ ] **Step 4: Run — PASS.**
- [ ] **Step 5: Commit** `feat(ai): completion strip above the chat composer`

---

### Task 4: thread di messaggi

**Files:**
- Create: `lib/features/rapportino/ai_chat/ai_chat_thread.dart`
- Test: `test/features/rapportino/ai_chat/ai_chat_thread_test.dart`

**Interfaces:**
- Consumes: `ChatMessage` (Task 1).
- Produces:
  `class AiChatThread extends StatefulWidget { const AiChatThread({super.key, required this.messages, required this.thinking, required this.thinkingLabel, this.speakingLastReply = false, this.onSpeakLastReply, this.failedMessageId, this.onRetryFailed}); }`
  Keys: `ValueKey('ai-chat-thread')`, `ValueKey('ai-msg-<id>')`, `ValueKey('ai-thinking')`, `ValueKey('ai-msg-retry')`.

- [ ] **Step 1: Write the failing test**

```dart
testWidgets('renders operator and assistant bubbles, then a thinking bubble', (tester) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: AiChatThread(
    messages: const [
      ChatMessage(id: 'm1', role: ChatRole.operator, text: 'Ho sostituito la valvola', source: ChatSource.voice, at: null),
      ChatMessage(id: 'm2', role: ChatRole.assistant, text: 'Quanti materiali?', source: ChatSource.typed, at: null),
    ],
    thinking: true,
    thinkingLabel: 'Sto compilando il rapporto…',
  ))));
  expect(find.text('Ho sostituito la valvola'), findsOneWidget);
  expect(find.text('Quanti materiali?'), findsOneWidget);
  expect(find.byKey(const ValueKey('ai-thinking')), findsOneWidget);
});
```

- [ ] **Step 2: Run — FAIL.**
- [ ] **Step 3: Implement** `ListView` con bolle (operatore a destra, assistente a sinistra), icona microfono per `voice`, bolla "thinking" finale quando `thinking`, `ScrollController` che scorre in fondo a ogni cambio (in `didUpdateWidget`), e il bottone Riprova sulla bolla identificata da `failedMessageId`.
- [ ] **Step 4: Run — PASS.**
- [ ] **Step 5: Commit** `feat(ai): chat thread widget`

---

### Task 5: composer compatto

**Files:**
- Create: `lib/features/rapportino/ai_chat/ai_chat_composer.dart`
- Modify: `lib/features/rapportino/ai_report/ai_describe_step.dart` (esporta `MicOrb` pubblico, o sposta l'orb nel nuovo file e importa)
- Test: `test/features/rapportino/ai_chat/ai_chat_composer_test.dart`

**Interfaces:**
- Produces:
  `class AiChatComposer extends StatefulWidget { const AiChatComposer({super.key, required this.controller, required this.recording, required this.busy, required this.writing, required this.micEnabled, required this.onMic, required this.onToggleWriting, required this.onSend, required this.onTextChanged}); }`
  Keys: `ValueKey('ai-chat-composer')`, `ValueKey('ai-chat-send')`, `ValueKey('ai-description-field')`, `ValueKey('ai-toggle-writing')`.
- `onSend` è chiamato solo con testo non vuoto e `busy == false`.

- [ ] **Step 1: Write the failing test**

```dart
testWidgets('send is enabled only with text and not busy', (tester) async {
  final ctrl = TextEditingController();
  var sent = 0;
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: AiChatComposer(
    controller: ctrl, recording: false, busy: false, writing: true, micEnabled: true,
    onMic: () {}, onToggleWriting: () {}, onSend: () => sent++, onTextChanged: () {}))));
  expect(tester.widget<IconButton>(find.byKey(const ValueKey('ai-chat-send'))).onPressed, isNull);
  await tester.enterText(find.byKey(const ValueKey('ai-description-field')), 'Valvola sostituita');
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('ai-chat-send')));
  expect(sent, 1);
});
```

- [ ] **Step 2: Run — FAIL.**
- [ ] **Step 3: Implement** composer: riga con orb (mic), toggle scrivere/voce, campo testo (quando `writing`), bottone invio. Riusa lo stile esistente (Archivo/mono, `context.colors`).
- [ ] **Step 4: Run — PASS.**
- [ ] **Step 5: Commit** `feat(ai): compact chat composer`

---

### Task 6: cablaggio nello screen

**Files:**
- Modify: `lib/features/rapportino/ai_copilot_screen.dart` (stato, `_adopt`, `_run` success path, `build`, `_buildFooter` describe)
- Test: `test/features/rapportino/ai_copilot_screen_test.dart` (estendere)

**Interfaces:**
- Consumes: tutto quanto sopra.
- Produces (stato interno):
  - `List<ChatMessage> _messages`
  - `String? _failedMessageId`
  - in `build` describe: `Column(children: [Expanded(AiChatThread(...)), AiCompletionStrip(completion: AiChatCompletion.fromDraft(_draft)), AiChatComposer(...)])`
  - footer describe: un solo `AppButton(key: ValueKey('ai-controlla'), label: 'Controlla', onPressed: _sessionId == null || _aiBlocked ? null : () => setState(() { _step = _AiStep.review; _writing = false; }))`

- [ ] **Step 1: Write the failing tests**

```dart
testWidgets('resuming shows every server turn in the thread', (tester) async { /* GET detail con 2 turni → entrambe le bolle */ });
testWidgets('a successful turn appends operator + assistant and stays on describe', (tester) async {
  /* invia turno → due nuove bolle; ancora su AiChatThread; nessun passaggio a review */
});
testWidgets('Controlla is always enabled and opens the review', (tester) async {
  /* draft vuoto → il bottone è abilitato, tap → AiReviewStep visibile */
});
testWidgets('a failed turn keeps the operator bubble with retry', (tester) async { /* 500 → bolla operatore + ai-msg-retry */ });
```

- [ ] **Step 2: Run — FAIL.**
- [ ] **Step 3: Implement**

1. `_adopt`: `_messages = ChatMessage.fromTurns(d.turns)`.
2. Success path di `_run`: append del messaggio operatore (testo `o.text`; se voce → `ChatMessage.operatorVoice(id: o.key)`) PRIMA della chiamata (subito dopo la validazione) e del messaggio assistente dopo; **rimuovere** il blocco che imposta `_step = _AiStep.review`; `_failedMessageId` impostato in `_fail`, azzerato al successo; `onRetryFailed` → `_retryFailed`.
3. Build: sostituire `replyBubble` + `AiDescribeStep` con thread/striscia/composer; rimuovere l'uso di `_assistantReply` nella UI (resta per TTS dell'ultimo messaggio assistente: `onSpeakLastReply`).
4. Footer describe: CTA `Controlla` come sopra; rimuovere "Genera il rapporto"/`_send` dal footer.
- [ ] **Step 4: Run — PASS.**
- [ ] **Step 5: Commit** `feat(ai): chat-based describe phase with completion strip`

---

### Task 7: pulizia e ritorno a Descrivi

**Files:**
- Modify: `lib/features/rapportino/ai_copilot_screen.dart` (`_buildFooter` review: il link "Descrivi di nuovo" resta e riporta al thread)
- Modify: `lib/features/rapportino/ai_report/ai_describe_step.dart` (rimuovere il widget se non più referenziato)
- Test: `test/features/rapportino/ai_copilot_screen_test.dart`

- [ ] **Step 1: Test** — "Descrivi di nuovo" da review riporta al thread con i messaggi intatti e `_writing` coerente; nessun riferimento residuo ad `AiDescribeStep`.
- [ ] **Step 2: Run — FAIL.**
- [ ] **Step 3: Implement** pulizia; `flutter analyze` verde (via CI).
- [ ] **Step 4: Run — PASS.**
- [ ] **Step 5: Commit** `chore(ai): retire the old describe step`

---

## Verifica finale

- CI mobile (repo pubblico) su `flutter analyze` + `flutter test` verde.
- A mano, su device (owner): riaprire una sessione esistente e vedere il thread; inviare un vocale; controllare che una domanda del modello resti nel thread; "Controlla" aprire la revisione con voci mancanti.
