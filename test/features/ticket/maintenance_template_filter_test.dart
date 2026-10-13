// dart format width=100
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/features/ticket/ticket_providers.dart';

/// The picker's filter, tested on its own — the "Modello checklist" field must offer only the
/// templates a NEW ticket may actually resolve: `isActive` and with a published version to snapshot.
/// The web form applies the same rule (`TicketCreatePanel.tsx`: `isActive && latestPublishedVersion
/// != null`); a template that fails either test is hidden, not disabled, so this widget-level rule is
/// what keeps the mobile picker matching it.
MaintenanceTemplate row(
  String id, {
  bool isActive = true,
  int? latestPublishedVersion = 1,
}) => MaintenanceTemplate(
  id: id,
  origin: 'System',
  name: 'Modello $id',
  isActive: isActive,
  latestPublishedVersion: latestPublishedVersion,
);

void main() {
  test('offers only active templates with a published version', () {
    final rows = [
      row('ok'),
      row('inactive', isActive: false),
      row('draft', latestPublishedVersion: null),
      row('tenant-ok', latestPublishedVersion: 5),
    ];

    final offered = assignableMaintenanceTemplates(rows);

    expect(offered.map((t) => t.id), ['ok', 'tenant-ok']);
  });

  test('an empty catalogue offers nothing', () {
    expect(assignableMaintenanceTemplates(const []), isEmpty);
  });

  test('a catalogue where every template is retired offers nothing', () {
    final rows = [
      row('a', isActive: false),
      row('b', latestPublishedVersion: null),
    ];
    expect(assignableMaintenanceTemplates(rows), isEmpty);
  });
}
