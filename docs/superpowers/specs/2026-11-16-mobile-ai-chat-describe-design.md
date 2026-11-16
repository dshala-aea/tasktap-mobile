# Mobile AI assistant — chat nella fase Descrivi

Data: 2026-11-16 · EPIC 24 / AI-M1 (`12493t4wnfg`) · Owner: Daniel

## Intent e perché

Il flusso AI del mobile oggi è un wizard a due passi (Descrivi → Controlla) che mostra **solo
l'ultima** risposta dell'assistente. Il tecnico che parla non vede il filo della conversazione, non
vede le domande a cui ha già risposto, e non capisce quanto manca al rapportino. Il server invece ha
già tutto: `GET /ai/conversations/{id}` restituisce i turni operatore/assistente
(`AiConversationTurn`), e il modello già chiede ciò che manca (categorie obbligatorie: tecnici,
materiali).

Questa modifica rende **solo la fase Descrivi** una chat: thread persistente, domande come messaggi,
stato di completamento sempre visibile. Revisione a schede e firma restano com'erano.

## Goal

1. Thread chat nella fase Descrivi: messaggi operatore (audio/testo) e assistente, con ripresa
   completa della conversazione quando si riapre la sessione.
2. Striscia "Stato rapportino" persistente sopra il composer: cosa è completo, cosa manca, quando si
   può revisionare.
3. "Controlla" **sempre abilitato**; passa in risalto quando le categorie obbligatorie sono
   soddisfatte.
4. Stati già esistenti preservati: invio in corso, "sta pensando", turno fallito con Riprova, quota
   esaurita, microfono negato/disattivato, TTS facoltativo della risposta.

## Non-goal

- Nessun cambiamento alla revisione a schede né alla firma.
- Nessuna modifica al pipeline voce (ADR-0023: il recording è l'input, niente ASR) né al prompt.
- Nessun endpoint nuovo: turni e draft sono già nel `GET` di ripresa; ogni turno restituisce il
  draft aggiornato (`AiConversationTurnResponse`).
- Nessun streaming token-per-token.

## Anti-goal

- Trasformare la revisione in messaggi (perde la lettura strutturata prima della firma).
- Introdurre stato di completamento calcolato in modo diverso dal gate di invio del server.
- Perdere il retry di un turno non inviato.

## Vincoli

- Nessun PII nei payload del modello (invariato).
- Confirm risolve, non crea; la Firma resta una route sull'id locale scritto da Conferma.
- Il gate reale dei dati resta lato server (`CanInvia`): la striscia è un indicatore, non un guard.
- Motion ridotto rispettato; target ≥44dp; contrasto come DESIGN.md.

## Approcci considerati

- **A — striscia di stato fissa sopra il composer, thread di messaggi (SCELTO).** Legge il draft già
  presente in memoria e lo stato è sempre visibile senza scorrere.
- **B — solo messaggi del modello** (l'assistente dice cosa manca): costo minimo, stato non
  persistente, chi scorre indietro lo perde. Scartato.
- **C — indicatore numerico "3/4"** con dettaglio al tap: compatto ma nasconde quale voce manca.
  Scartato.

## Decisioni dell'owner

1. Chat solo nella fase Descrivi; revisione e firma invariate.
2. "Controlla" sempre attivo.
3. Materiali possono esserci o non esserci: la voce Materiali è soddisfatta da almeno una riga **o**
   dal flag "nessun materiale utilizzato".

## Design

### Modello messaggi

`ChatMessage { id, role: operator|assistant, text, source: typed|voice, at }`, in stato locale
sullo schermo (o un `ValueNotifier`/controller dedicato per non far ricostruire tutta la schermata a
ogni turno).

- Alla ripresa: `detail.turns` → lista messaggi (role `Operator`/`Assistant`; `source` Voice mostra
  l'icona microfono); nessun replay TTS automatico.
- All'invio: aggiunta ottimistica del messaggio operatore (audio mostrato come vocale con il testo
  del turno), poi, alla risposta, messaggio assistente con `assistantReplyText` e `_draft =
  result.draft`.
- Turno fallito: il messaggio operatore resta nel thread con lo stato "non inviato" e l'azione
  Riprova (riusa `_Outgoing`/`_failed` esistenti); nessun messaggio assistente inventato.
- "Sta pensando": bolla assistente temporanea con il thinking label già esistente, sostituita dalla
  risposta o rimossa al fallimento.

### Stato di completamento

Calcolato dal `AiCopilotDraftDto` in memoria (aggiornato a ogni turno e alla ripresa):

| Voce | Soddisfatta quando |
|---|---|
| Tecnici | `workers.isNotEmpty` |
| Materiali | `materials.isNotEmpty` **oppure** `materialiNotRequired` |
| Controlli | `controlli.isNotEmpty` — facoltativa: grigia "se previsti" quando il ticket non ne ha |
| Descrizione | `activities.isNotEmpty` oppure `diagnosi`/`soluzione` presenti |

`AiCopilotDraftDto` guadagna `materialiNotRequired` (il wire lo contiene già).

Striscia: quattro chip con ✓ / ! / ○, e una riga di sintesi:
- obbligatorie soddisfatte → "Pronto per la revisione" (chip in verde, CTA pieno);
- altrimenti → "Manca: materiali" (o "tecnici").
"Controlla" resta sempre tappabile anche quando la riga segnala qualcosa mancante.

### File toccati (indicativo)

- `lib/data/ai/ai_api_client.dart` — `materialiNotRequired` su `AiCopilotDraftDto`.
- `lib/features/rapportino/ai_chat/` (nuovo) — `chat_message.dart`, `ai_chat_thread.dart` (bolle,
  auto-scroll), `ai_completion_strip.dart` (chip + sintesi + modello di completamento).
- `lib/features/rapportino/ai_copilot_screen.dart` — stato messaggi, idratazione da `_adopt`,
  append su invio/risposta, fase Descrivi composta da thread + striscia + composer esistente.
- `lib/features/rapportino/ai_report/ai_describe_step.dart` — resta il composer (mic/text), non più
  l'intera fase.

### Test (widget/unit, senza rete)

- Ripresa: `detail.turns` produce il thread nell'ordine giusto, con sorgente audio marcata.
- Invio: messaggio operatore ottimistico → risposta assistente → due bolle e draft aggiornato.
- Fallimento: bolla "non inviato" + Riprova che riusa lo stesso turno.
- Striscia: tecnici mancanti → ! e "Manca: tecnici"; materiali assenti con flag attivo → ✓;
  tutto soddisfatto → "Pronto per la revisione" e CTA in risalto.
- Controlla sempre abilitato.
- a11y: label semantiche delle bolle, ordine di lettura, reduce-motion.

## Lasciato al builder

- Stile preciso delle bolle (raggio, colori, spaziature) dentro i token Vetro esistenti.
- Animazione di ingresso dei messaggi e dello "sta pensando".
- Copy esatta delle chip e della riga di sintesi.
