import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/utils/error_message.dart';

/// The one rule this file exists to hold: **nothing a technician reads is the exception.**
///
/// Five surfaces printed `e.toString()` before this function existed, and two of them were the
/// worst places in the app for it — the line under "Invia rapportino", and the subtitle of the
/// "Invio fallito" card. Both are read at the moment a signed record may or may not have left the
/// phone. So the assertions below are mostly negative: they check what is *absent* from the
/// output, because a regression here does not throw, it just quietly puts a stack trace back in
/// front of someone standing in a plant room.
void main() {
  final request = RequestOptions(path: '/api/reports/submit');

  DioException withStatus(int status, {Object? body}) => DioException(
    requestOptions: request,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: request, statusCode: status, data: body),
  );

  group('transport failures read as the radio, not the app', () {
    for (final type in [
      DioExceptionType.connectionError,
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
    ]) {
      test('$type says the connection is missing and names the action', () {
        final message = humanErrorMessage(
          DioException(
            requestOptions: request,
            type: type,
            error: 'SocketException: Failed host lookup: api.tasktap.it',
          ),
          azione: 'inviare il rapportino',
        );

        expect(message, contains('Nessuna connessione'));
        expect(message, contains('inviare il rapportino'));
        expect(message, isNot(contains('SocketException')));
      });
    }

    test('a response with no status code is treated as transport, not as a server answer', () {
      final message = humanErrorMessage(
        DioException(requestOptions: request, type: DioExceptionType.unknown),
      );
      expect(message, contains('Nessuna connessione'));
    });
  });

  group('server answers', () {
    test('401 sends them to sign in again rather than reporting a number', () {
      expect(humanErrorMessage(withStatus(401)), contains('Sessione scaduta'));
    });

    test('403 names the refusal and where to resolve it', () {
      final message = humanErrorMessage(withStatus(403));
      expect(message, contains('permesso'));
      expect(message, contains('ufficio'));
    });

    test('404 does not read as the technician having lost something', () {
      expect(humanErrorMessage(withStatus(404)), contains('Non trovato'));
    });

    test('429 asks for patience instead of a retry loop', () {
      expect(humanErrorMessage(withStatus(429)), contains('occupato'));
    });

    // The status code is the part a technician cannot act on and the part that reads as their
    // fault. `Errore server (503)` was the old wording; the number must not come back.
    for (final status in [500, 502, 503, 504]) {
      test('$status never prints the code', () {
        final message = humanErrorMessage(withStatus(status));
        expect(message, contains('Il server non risponde'));
        expect(message, isNot(contains('$status')));
      });
    }
  });

  group('ProblemDetails', () {
    test('the server\'s own sentence wins, because it knows which rule was broken', () {
      final message = humanErrorMessage(
        withStatus(409, body: {'detail': 'Esiste già una sessione cantiere attiva'}),
      );
      expect(message, contains('Esiste già una sessione cantiere attiva.'));
    });

    test('an already-punctuated sentence is not given a second full stop', () {
      final message = humanErrorMessage(withStatus(400, body: {'detail': 'Data non valida.'}));
      expect(message, contains('Data non valida.'));
      expect(message, isNot(contains('..')));
    });

    test('a leaked .NET exception is refused in favour of the generic sentence', () {
      final message = humanErrorMessage(
        withStatus(400, body: {'detail': 'System.InvalidOperationException: sequence contains no'}),
      );
      expect(message, isNot(contains('System.')));
      expect(message, contains('Controlla i dati inseriti'));
    });

    test('a stack trace masquerading as detail is refused', () {
      final message = humanErrorMessage(
        withStatus(422, body: {'detail': '   at TaskTap.Reports.Submit(Guid id)'}),
      );
      expect(message, isNot(contains('   at ')));
    });

    test('an essay is refused — a snackbar is not a log viewer', () {
      final message = humanErrorMessage(withStatus(400, body: {'detail': 'x' * 400}));
      expect(message, isNot(contains('xxx')));
    });

    test('a non-map body cannot crash the humaniser', () {
      expect(humanErrorMessage(withStatus(400, body: 'plain text body')), isNotEmpty);
    });
  });

  group('everything else', () {
    test('a non-Dio throwable never surfaces its own text', () {
      final message = humanErrorMessage(StateError('Bad state: no element'));
      expect(message, 'Errore imprevisto. Riprova.');
      expect(message, isNot(contains('Bad state')));
    });
  });

  group('reassurance', () {
    test('naming an action adds the fact the technician actually needs', () {
      final message = humanErrorMessage(withStatus(500), azione: 'inviare il rapportino');
      expect(message, contains('Niente è andato perso.'));
    });

    test('it is withheld when the caller says the work is not safe', () {
      final message = humanErrorMessage(
        withStatus(500),
        azione: 'inviare il rapportino',
        workIsSafe: false,
      );
      expect(message, isNot(contains('Niente è andato perso')));
    });

    test('no action, no claim about safety we cannot back', () {
      expect(humanErrorMessage(withStatus(500)), isNot(contains('Niente è andato perso')));
    });
  });
}
