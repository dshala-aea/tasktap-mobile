import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/badge/badge_models.dart';

void main() {
  test('BadgeScanResult_fromWire_MapsEveryBackendName', () {
    const names = {
      'Accepted': BadgeScanResult.accepted,
      'NotAssigned': BadgeScanResult.notAssigned,
      'Revoked': BadgeScanResult.revoked,
      'Expired': BadgeScanResult.expired,
      'Invalid': BadgeScanResult.invalid,
      'OpenElsewhere': BadgeScanResult.openElsewhere,
      'PayrollLocked': BadgeScanResult.payrollLocked,
      'Replayed': BadgeScanResult.replayed,
    };
    names.forEach((wire, value) {
      expect(BadgeScanResult.fromWire(wire), value, reason: wire);
      expect(BadgeScanResult.fromWire(wire.toLowerCase()), value, reason: 'case-insensitive');
    });
    expect(BadgeScanAction.fromWire('None'), BadgeScanAction.none);
    expect(BadgeScanAction.fromWire('Opened'), BadgeScanAction.opened);
    expect(BadgeScanAction.fromWire('closed'), BadgeScanAction.closed);
  });

  test('fromWire_UnknownAndNull_AreUnknown', () {
    expect(BadgeScanResult.fromWire(null), BadgeScanResult.unknown);
    expect(BadgeScanResult.fromWire('Teleported'), BadgeScanResult.unknown);
    expect(BadgeScanResult.fromWire('unknown'), BadgeScanResult.unknown);
    expect(BadgeScanResult.fromWire('3'), BadgeScanResult.unknown);
    expect(BadgeScanAction.fromWire(null), BadgeScanAction.unknown);
    expect(BadgeScanAction.fromWire('Exploded'), BadgeScanAction.unknown);
  });

  test('BadgeCard_fromJson_ParsesAllFields_NullPhoto', () {
    final c = BadgeCard.fromJson({
      'badgeId': 'b-1',
      'token': 'tok',
      'expiresInSeconds': 60,
      'displayName': 'Mario Rossi',
      'photoUrl': null,
      'employerName': 'ACME Srl',
      'status': 'Active',
    });
    expect(c.badgeId, 'b-1');
    expect(c.token, 'tok');
    expect(c.expiresInSeconds, 60);
    expect(c.displayName, 'Mario Rossi');
    expect(c.photoUrl, isNull);
    expect(c.employerName, 'ACME Srl');
    expect(c.status, 'Active');
  });

  test('BadgeScanOutcome_fromJson_WorkerNull_ForInvalid', () {
    final o = BadgeScanOutcome.fromJson({
      'result': 'Invalid',
      'action': 'None',
      'workLogId': null,
      'worker': null,
    });
    expect(o.result, BadgeScanResult.invalid);
    expect(o.action, BadgeScanAction.none);
    expect(o.workLogId, isNull);
    expect(o.worker, isNull);

    final ok = BadgeScanOutcome.fromJson({
      'result': 'Accepted',
      'action': 'Opened',
      'workLogId': 'w-1',
      'worker': {'displayName': 'Mario', 'photoUrl': 'http://x/p.jpg', 'employerName': 'ACME'},
    });
    expect(ok.worker!.displayName, 'Mario');
    expect(ok.worker!.photoUrl, 'http://x/p.jpg');
    expect(ok.workLogId, 'w-1');
  });
}
