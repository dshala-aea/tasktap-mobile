// dart format width=100
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasktap_mobile/data/reports/customer_copy_recipient_store.dart';
import 'package:tasktap_mobile/data/reports/submit_report_request.dart';

/// The customer's copy of a signed rapportino (ClickUp 12493t4wxvm): the address the technician
/// confirms at Riepilogo travels with the submit. The wire name is asserted as a string — a wrong
/// field name compiles, sends, and silently binds nothing server-side.
void main() {
  SubmitReportRequest request({String? recipient}) => SubmitReportRequest(
    id: 'r-1',
    locationId: 'loc-1',
    title: 'Intervento',
    customerCopyRecipient: recipient,
  );

  group('SubmitReportRequest.customerCopyRecipient wire shape', () {
    test('is sent under customerCopyRecipient, trimmed', () {
      expect(request(recipient: '  cliente@example.com ').toJson()['customerCopyRecipient'],
          'cliente@example.com');
    });

    test('null or blank is omitted — the shape every older build sends', () {
      expect(request().toJson().containsKey('customerCopyRecipient'), isFalse);
      expect(request(recipient: '   ').toJson().containsKey('customerCopyRecipient'), isFalse);
    });
  });

  group('CustomerCopyRecipientStore', () {
    late CustomerCopyRecipientStore store;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      store = CustomerCopyRecipientStore(prefs: SharedPreferences.getInstance);
    });

    test('no decision yet reads as null and sends nothing', () async {
      expect(await store.read('r-1'), isNull);
      expect(await store.recipientForSubmit('r-1'), isNull);
    });

    test('a confirmed address is stored trimmed and goes out with the submit', () async {
      await store.write('r-1', '  cliente@example.com ');
      expect(await store.read('r-1'), 'cliente@example.com');
      expect(await store.recipientForSubmit('r-1'), 'cliente@example.com');
    });

    test('an empty string means "do not send" and is distinguishable from "no decision"', () async {
      await store.write('r-1', '');
      expect(await store.read('r-1'), '');
      expect(await store.recipientForSubmit('r-1'), isNull);
    });

    test('decisions are per report', () async {
      await store.write('r-1', 'a@example.com');
      await store.write('r-2', '');
      expect(await store.recipientForSubmit('r-1'), 'a@example.com');
      expect(await store.recipientForSubmit('r-2'), isNull);
      expect(await store.read('r-3'), isNull);
    });
  });
}
