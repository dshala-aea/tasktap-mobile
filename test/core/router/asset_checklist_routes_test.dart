import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/router/app_router.dart';

void main() {
  test('the asset checklist lives under the ticket route', () {
    expect(AppRoutes.ticketAssetChecklistPath('t1'), '/ticket/t1/assets');
  });
}
