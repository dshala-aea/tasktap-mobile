import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/reports/submit_report_request.dart';

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
        reason: 'the server has no such field; it would deserialize to Guid.Empty',
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
}
