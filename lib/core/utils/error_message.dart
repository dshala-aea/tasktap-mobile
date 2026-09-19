// dart format width=100
import 'package:dio/dio.dart';

// ══════════════════════════════════════════════════════════════════════════════
// humanErrorMessage
//
// One place that turns a thrown object into something a technician can act on.
//
// Before this existed, five surfaces printed the exception itself. Two of them
// were the worst possible places for it: the red line under "Invia rapportino",
// and the subtitle of the "Invio fallito" card — the two moments where the only
// questions are *did I lose the work* and *what do I do now*. `DioException
// [connection error]: The connection errored: Failed host lookup` answers
// neither, and reads to the person holding the phone as the app breaking rather
// than the building having no signal.
//
// The rule this encodes: the technician is told what happened and what to do.
// The exception text stays in the logs, where the person who can read it is.
//
// Status codes are deliberately not printed. "Errore server (503)" is the same
// sentence as "Errore server" plus a number nobody on a site can use, and the
// number is the part that reads as a fault they caused.
// ══════════════════════════════════════════════════════════════════════════════

/// What went wrong, in the technician's terms.
///
/// [azione] names the thing that did not happen, in the infinitive, so the
/// message can say what is being retried — `'inviare il rapportino'`,
/// `'salvare la foto'`. Omit it and the message stays generic but still honest.
///
/// [workIsSafe] appends the reassurance that nothing was lost. Pass false only
/// where that is genuinely not true; the default is true because every write
/// path in this app either queues locally or leaves the form filled in.
String humanErrorMessage(Object error, {String? azione, bool workIsSafe = true}) {
  final core = _core(error, azione);

  // Only worth saying where a technician would otherwise assume the opposite —
  // that is, when something they typed or captured was in flight.
  if (workIsSafe && azione != null) return '$core Niente è andato perso.';
  return core;
}

String _core(Object error, String? azione) {
  if (error is! DioException) return 'Errore imprevisto. Riprova.';

  final status = error.response?.statusCode;

  // No response at all: the radio, not the server.
  if (status == null || _isTransport(error.type)) {
    return azione == null
        ? 'Nessuna connessione. Riprova quando torni online.'
        : 'Nessuna connessione: impossibile $azione ora. Riprova quando torni online.';
  }

  switch (status) {
    case 401:
      return 'Sessione scaduta. Accedi di nuovo per continuare.';
    case 403:
      return 'Non hai il permesso per questa operazione. Chiedi in ufficio.';
    case 404:
      return 'Non trovato sul server. Potrebbe essere stato eliminato.';
    case 408:
    case 429:
      return 'Il server è occupato. Attendi qualche istante e riprova.';
  }

  if (status >= 500) {
    return 'Il server non risponde. Riprova tra qualche minuto.';
  }

  // 4xx: the server usually has a better sentence than we can write, because it
  // knows which rule was broken. Use it when it is prose and not a stack.
  return _serverSentence(error.response?.data) ??
      'Il server ha rifiutato la richiesta. Controlla i dati inseriti e riprova.';
}

bool _isTransport(DioExceptionType type) =>
    type == DioExceptionType.connectionTimeout ||
    type == DioExceptionType.sendTimeout ||
    type == DioExceptionType.receiveTimeout ||
    type == DioExceptionType.connectionError ||
    type == DioExceptionType.cancel;

/// The server's own explanation, when it wrote one for a human.
///
/// The backend answers `application/problem+json`, so `detail` is authored text
/// and `title` is a short label. Anything carrying stack-trace or type-name
/// shape is rejected — a leaked `System.InvalidOperationException` is exactly
/// what this function exists to keep off the screen.
String? _serverSentence(Object? data) {
  if (data is! Map) return null;

  for (final key in const ['detail', 'title', 'message']) {
    final value = data[key];
    if (value is! String) continue;
    final text = value.trim();
    if (text.isEmpty || text.length > 200) continue;
    if (_looksTechnical(text)) continue;
    return text.endsWith('.') || text.endsWith('!') || text.endsWith('?') ? text : '$text.';
  }
  return null;
}

bool _looksTechnical(String text) =>
    text.contains('Exception') ||
    text.contains('Error:') ||
    text.contains('   at ') ||
    text.contains('System.') ||
    text.contains('Microsoft.') ||
    text.contains('null reference');
