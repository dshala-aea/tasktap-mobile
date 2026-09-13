// dart format width=100
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/ferie/absence_request_api_client.dart';

// This file only tests pure Dart JSON parsing (no Dio/network mocking needed — AbsenceRequestDto
// is a plain fromJson factory). Any real HTTP-call-level assertions belong in Task 7/8's widget
// tests via a fake AbsenceRequestApiClient subclass, exactly like agenda_list_screen_test.dart's
// `_FakeAgendaApiClient` pattern — do not add a Dio-mocking dependency for this file; re-grep
// mobile/pubspec.yaml first if a future task genuinely needs one, none is added by this plan.

void main() {
  test('AbsenceRequestDto.fromJson parses the full wire shape', () {
    final dto = AbsenceRequestDto.fromJson({
      'id': 'ar-1',
      'requestedByUserId': 'user-1',
      'createdByUserId': 'user-1',
      'type': 0,
      'startDate': '2026-09-10',
      'endDate': '2026-09-12',
      'startTime': null,
      'endTime': null,
      'reason': 'Vacanza',
      'status': 0,
      'decidedByUserId': null,
      'decidedAt': null,
      'decisionReason': null,
    });

    expect(dto.id, 'ar-1');
    expect(dto.type, 0);
    expect(dto.status, 0);
    expect(dto.startDate, DateTime(2026, 9, 10));
    expect(dto.endDate, DateTime(2026, 9, 12));
  });

  test('AbsenceRequestDto.fromJson handles a partial-time Permesso', () {
    final dto = AbsenceRequestDto.fromJson({
      'id': 'ar-2',
      'requestedByUserId': 'user-1',
      'createdByUserId': 'user-1',
      'type': 1,
      'startDate': '2026-09-10',
      'endDate': '2026-09-10',
      'startTime': '09:00:00',
      'endTime': '11:00:00',
      'reason': null,
      'status': 0,
      'decidedByUserId': null,
      'decidedAt': null,
      'decisionReason': null,
    });

    expect(dto.startTime, '09:00:00');
    expect(dto.endTime, '11:00:00');
  });
}
