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

  group('the id a send may carry', () {
    test('an offered choice is sent as chosen', () {
      final rows = [row('ok'), row('other')];
      expect(offerableMaintenanceTemplateId('ok', rows), 'ok');
    });

    test('a choice the catalogue has retired is dropped', () {
      // The picker stopped offering it, so the form no longer holds it — but the id can still be in
      // the queued row a repair re-sends. The server answers such a template with a 400 whose body
      // carries no `field`, and the create queue can only classify a 404-with-field as repairable:
      // the row would retry forever. Dropping it here is what keeps it off the wire.
      final rows = [row('ok'), row('gone', isActive: false)];
      expect(offerableMaintenanceTemplateId('gone', rows), isNull);
    });

    test('a choice with no published version is dropped', () {
      final rows = [row('ok'), row('draft', latestPublishedVersion: null)];
      expect(offerableMaintenanceTemplateId('draft', rows), isNull);
    });

    test('no choice stays no choice', () {
      expect(offerableMaintenanceTemplateId(null, [row('ok')]), isNull);
    });

    test('a catalogue that has not synced yet passes the choice through', () {
      // An empty catalogue means "this device has nothing to judge by", not "nothing is valid" —
      // failing closed would strip the template from every queued ticket on a device that has not
      // synced since installing, which is the picker working exactly as the ticket was created.
      expect(offerableMaintenanceTemplateId('tpl-1', const []), 'tpl-1');
    });

    test('a synced catalogue of only retired templates is not an unsynced one', () {
      // The distinction the empty check above rests on: rows came back, every one of them is simply
      // unofferable. That is a judgement, and it fails closed.
      final rows = [
        row('a', isActive: false),
        row('b', latestPublishedVersion: null),
      ];
      expect(offerableMaintenanceTemplateId('a', rows), isNull);
    });
  });
}
