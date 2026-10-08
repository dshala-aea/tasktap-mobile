import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/router/app_router.dart';
import 'package:tasktap_mobile/domain/checklist/checklist_items.dart';

void main() {
  test('the asset checklist lives under the ticket route', () {
    expect(AppRoutes.ticketAssetChecklistPath('t1'), '/ticket/t1/assets');
  });

  test('the editable checklist hangs off the rapportino editor and carries focus and filter', () {
    expect(AppRoutes.reportAssetChecklistPath('r1'), '/altro/rapportini/editor/r1/assets');
    expect(
      AppRoutes.reportAssetChecklistPath('r1', focusAssetId: 'a 1', filter: ChecklistFilter.requiredMissing),
      '/altro/rapportini/editor/r1/assets?focus=a+1&filter=requiredMissing',
    );
  });
}
