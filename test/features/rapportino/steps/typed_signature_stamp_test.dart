import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/core/time/business_time.dart';
import 'package:tasktap_mobile/features/rapportino/steps/step_riepilogo.dart';

void main() {
  // 22:30Z on 10 July: 00:30 on 11 July in Rome, whatever the device zone.
  final clock = DateTime.utc(2026, 7, 10, 22, 30);

  test('stamp is the business-zone time', () {
    expect(typedSignatureStamp(BusinessTime('Europe/Rome', clock: () => clock)), '11/07/2026 00:30');
  });

  test('stamp follows the tenant zone, not the device', () {
    expect(
      typedSignatureStamp(BusinessTime('America/New_York', clock: () => clock)),
      '10/07/2026 18:30',
    );
  });
}
