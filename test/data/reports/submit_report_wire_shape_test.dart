import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/reports/submit_report_request.dart';
import 'package:tasktap_mobile/domain/reports/customer_signature_absence_reason.dart';

/// The wire names a rapportino submission actually sends.
///
/// These assert strings rather than behaviour on purpose. A field name is the one kind of contract
/// break that no amount of local testing catches: the app compiles, the UI works, the request is
/// sent, and the server rejects it — or worse, accepts it and binds nothing.
///
/// This exists because `controlId` was sent for months where the server reads `ticketControlId`
/// (renamed by ADR-0012 when a report's answers started referencing the *ticket's* copy of a
/// checklist item rather than the template control). The server's field is a non-nullable Guid, so
/// the wrong name deserialized to `Guid.Empty`, which belongs to no ticket — and the ownership
/// guard rejected the whole submission. A technician who filled in the checklist could not send
/// their rapportino at all.
void main() {
  group('SubmitReportControlloDto wire shape', () {
    test('sends ticketControlId, not controlId', () {
      final json = const SubmitReportControlloDto(
        ticketControlId: 'a1b2c3d4-0000-0000-0000-000000000001',
        boolValue: true,
      ).toJson();

      expect(json['ticketControlId'], 'a1b2c3d4-0000-0000-0000-000000000001');
      expect(
        json.containsKey('controlId'),
        isFalse,
        reason:
            'the server has no such field; it would deserialize to Guid.Empty',
      );
    });

    test('omits the value fields it has no answer for', () {
      final json = const SubmitReportControlloDto(
        ticketControlId: 'ctrl-1',
        stringValue: 'ok',
      ).toJson();

      expect(json['stringValue'], 'ok');
      expect(json.containsKey('boolValue'), isFalse);
      expect(json.containsKey('dateValue'), isFalse);
    });

    test('sends a date as UTC ISO-8601', () {
      final json = SubmitReportControlloDto(
        ticketControlId: 'ctrl-1',
        dateValue: DateTime.utc(2026, 6, 15, 9, 30),
      ).toJson();

      expect(json['dateValue'], '2026-06-15T09:30:00.000Z');
    });

    /// A false answer is an answer — "the extinguisher is not present" is a finding, not a blank.
    test('keeps a false boolValue rather than dropping it', () {
      final json = const SubmitReportControlloDto(
        ticketControlId: 'ctrl-1',
        boolValue: false,
      ).toJson();

      expect(json['boolValue'], false);
      expect(json.containsKey('boolValue'), isTrue);
    });
  });

  group('SubmitReportRequest diagnosi/soluzione', () {
    const base = SubmitReportRequest(id: 'r1', locationId: 'l1', title: 'T');

    test('are omitted when null so the server keeps its own value', () {
      final json = base.toJson();
      expect(json.containsKey('diagnosi'), isFalse);
      expect(json.containsKey('soluzione'), isFalse);
    });

    test('are sent when set', () {
      final json = const SubmitReportRequest(
        id: 'r1',
        locationId: 'l1',
        title: 'T',
        diagnosi: 'Pompa bloccata',
        soluzione: 'Sostituita',
      ).toJson();
      expect(json['diagnosi'], 'Pompa bloccata');
      expect(json['soluzione'], 'Sostituita');
    });

    /// "" is the backend's explicit "clear" (null means keep), so it must reach the wire.
    test('an empty string is sent, not dropped', () {
      final json = const SubmitReportRequest(
        id: 'r1',
        locationId: 'l1',
        title: 'T',
        diagnosi: '',
        soluzione: '',
      ).toJson();
      expect(json['diagnosi'], '');
      expect(json['soluzione'], '');
    });
  });

  group('SubmitReportRequest cantiere link (P2-6)', () {
    const base = SubmitReportRequest(id: 'r1', locationId: 'l1', title: 'T');

    test('cantiereId is omitted when null — that is the server\'s "keep yours"', () {
      expect(base.toJson().containsKey('cantiereId'), isFalse);
    });

    test('cantiereId is sent when set, under the server\'s own name', () {
      final json = const SubmitReportRequest(
        id: 'r1',
        locationId: 'l1',
        title: 'T',
        cantiereId: 'c1',
      ).toJson();
      expect(json['cantiereId'], 'c1');
    });

    test('the claim list is always sent, empty included', () {
      expect(base.toJson()['consumedCantiereWorkLogClientIds'], isEmpty);

      final json = const SubmitReportRequest(
        id: 'r1',
        locationId: 'l1',
        title: 'T',
        cantiereId: 'c1',
        consumedCantiereWorkLogClientIds: ['punch-a', 'punch-b'],
      ).toJson();
      expect(json['consumedCantiereWorkLogClientIds'], ['punch-a', 'punch-b']);
    });
  });

  group('customer signature absence ("Il cliente non può firmare")', () {
    test('each reason goes out as its backend integer, never its name', () {
      // The server enum has no string converter, so a name would bind to the default (0, i.e.
      // Assente) — the exact silent-misbind this file exists to catch.
      const expected = {
        CustomerSignatureAbsenceReason.assente: 0,
        CustomerSignatureAbsenceReason.rifiuta: 1,
        CustomerSignatureAbsenceReason.altro: 2,
      };
      for (final entry in expected.entries) {
        final json = SubmitReportRequest(
          id: 'r1',
          locationId: 'l1',
          title: 'T',
          customerSignatureAbsenceReason: entry.key,
        ).toJson();
        expect(json['customerSignatureAbsenceReason'], entry.value);
        expect(json.containsKey('customerSignatureAbsenceNote'), isFalse);
      }
    });

    test('the note is trimmed and sent only when non-empty', () {
      const withNote = SubmitReportRequest(
        id: 'r1',
        locationId: 'l1',
        title: 'T',
        customerSignatureAbsenceReason: CustomerSignatureAbsenceReason.altro,
        customerSignatureAbsenceNote: '  Cliente in ospedale  ',
      );
      expect(withNote.toJson()['customerSignatureAbsenceNote'], 'Cliente in ospedale');

      const blankNote = SubmitReportRequest(
        id: 'r1',
        locationId: 'l1',
        title: 'T',
        customerSignatureAbsenceReason: CustomerSignatureAbsenceReason.assente,
        customerSignatureAbsenceNote: '   ',
      );
      expect(blankNote.toJson().containsKey('customerSignatureAbsenceNote'), isFalse);
    });

    test('a signed report never also carries an absence reason', () {
      final json = const SubmitReportRequest(
        id: 'r1',
        locationId: 'l1',
        title: 'T',
        customerSignatureAllegatoId: 'sig-cust',
        customerSignatureAbsenceReason: CustomerSignatureAbsenceReason.assente,
        customerSignatureAbsenceNote: 'non doveva esserci',
      ).toJson();

      expect(json['customerSignatureAllegatoId'], 'sig-cust');
      expect(json.containsKey('customerSignatureAbsenceReason'), isFalse);
      expect(json.containsKey('customerSignatureAbsenceNote'), isFalse);
    });
  });

  group('asset answers and instruments on the wire', () {
    test(
      'a note is sent when non-blank and omitted otherwise (a blank never wipes a stored note)',
      () {
        expect(
          const SubmitReportControlloDto(
            ticketControlId: 'c',
            numberValue: 0,
            note: 'manometro ok',
          ).toJson()['note'],
          'manometro ok',
        );
        expect(
          const SubmitReportControlloDto(
            ticketControlId: 'c',
            numberValue: 0,
          ).toJson().containsKey('note'),
          isFalse,
        );
        expect(
          const SubmitReportControlloDto(
            ticketControlId: 'c',
            note: '   ',
          ).toJson().containsKey('note'),
          isFalse,
        );
      },
    );

    test('0 is an answer: numberValue 0 reaches the wire', () {
      expect(
        const SubmitReportControlloDto(
          ticketControlId: 'c',
          numberValue: 0,
        ).toJson()['numberValue'],
        0,
      );
    });

    test(
      'strumenti are always serialised, as strumentoId + expiredAcknowledged only',
      () {
        const base = SubmitReportRequest(
          id: 'r1',
          locationId: 'l1',
          title: 'T',
        );
        expect(base.toJson()['strumenti'], isEmpty);
        final json = const SubmitReportRequest(
          id: 'r1',
          locationId: 'l1',
          title: 'T',
          strumenti: [
            SubmitReportStrumentoDto(
              strumentoId: 's1',
              expiredAcknowledged: true,
            ),
          ],
        ).toJson();
        expect(json['strumenti'], [
          {'strumentoId': 's1', 'expiredAcknowledged': true},
        ]);
      },
    );
  });
}
