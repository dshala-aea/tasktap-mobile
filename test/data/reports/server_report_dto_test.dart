// dart format width=100
// Response-shape test for GET /api/Reports/{id}.
//
// The OpenAPI snapshot has no schema for this response, so this fixture is the only pin on the
// shape. It mirrors the backend projection exactly:
//   backend: src/TaskTapAPI.Api/Controllers/ReportsController.cs  GetById (anonymous object:
//   header properties named one by one, then materiali / staff / observations = the EF entities
//   passed through whole), entities in src/TaskTapAPI.Core/Entities/{ReportStaff,ReportMateriale,
//   ReportControlObservation}.cs. System.Text.Json default => camelCase; `stato` is a raw int
//   (anonymous types do not inherit the entity's JsonStringEnumConverter); there is NO cantiereId.
// If the backend renames/adds a property, update the fixture from that file, not from this DTO.

import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/reports/server_report_dto.dart';

Map<String, dynamic> backendFixture() => {
  'id': '11111111-1111-1111-1111-111111111111',
  'tenantId': '22222222-2222-2222-2222-222222222222',
  'title': 'Sostituzione pompa',
  'scheduleId': null,
  'ticketId': '33333333-3333-3333-3333-333333333333',
  'customerId': '44444444-4444-4444-4444-444444444444',
  'details': 'Sostituita pompa; verificata tenuta',
  'insertedUserId': '55555555-5555-5555-5555-555555555555',
  'locationId': '66666666-6666-6666-6666-666666666666',
  'startedAt': null,
  'endedAt': null,
  'customerSignatureAllegatoId': null,
  'technicianSignatureAllegatoId': null,
  'technicianNotes': null,
  'closedAt': null,
  'isCompleted': false,
  'stato': 0,
  'inviatoAt': null,
  'controllatoAt': null,
  'controllatoDa': null,
  'fatturatoAt': null,
  'nonFatturabileAt': null,
  'createdAt': '2026-10-01T08:00:00Z',
  'updatedAt': null,
  'diagnosi': 'Pompa bloccata',
  'soluzione': 'Sostituita',
  'escludiManodopera': false,
  'dirittoIntervento': false,
  'extra': false,
  'importato': false,
  'externalId': null,
  'numero': 12,
  'materialiNotRequired': false,
  'customerSignoffText': 'Lavoro accettato',
  'customerSignoffAt': null,
  'isAiAssisted': false,
  'materiali': [
    {
      'id': 'aaaaaaaa-0000-0000-0000-000000000001',
      'tenantId': '22222222-2222-2222-2222-222222222222',
      'createdAt': '2026-10-01T08:00:00Z',
      'reportId': '11111111-1111-1111-1111-111111111111',
      'materialeId': '77777777-7777-7777-7777-777777777777',
      'freeTextName': null,
      'quantity': 2.5,
      'unitOfMeasure': 'pz',
      'unitPrice': 10.0,
      'notes': null,
      'magazzinoId': null,
    },
    {
      'id': 'aaaaaaaa-0000-0000-0000-000000000002',
      'reportId': '11111111-1111-1111-1111-111111111111',
      'materialeId': null,
      'freeTextName': 'Guarnizione',
      'quantity': 1,
      'unitOfMeasure': null,
      'unitPrice': null,
      'notes': 'a misura',
      'magazzinoId': null,
    },
  ],
  'staff': [
    {
      'id': 'bbbbbbbb-0000-0000-0000-000000000001',
      'reportId': '11111111-1111-1111-1111-111111111111',
      'userId': '55555555-5555-5555-5555-555555555555',
      'hoursWorked': 3.5,
      'kmTraveled': 12,
      'vehicle': 'Furgone',
      'costPerKm': 0.4,
      'notes': null,
      'startTime': '2026-10-01T07:00:00Z',
      'endTime': '2026-10-01T10:30:00Z',
      'pauseMinutes': 15,
    },
  ],
  'observations': [
    {
      'id': 'cccccccc-0000-0000-0000-000000000001',
      'reportId': '11111111-1111-1111-1111-111111111111',
      'ticketControlId': '99999999-9999-9999-9999-999999999999',
      'stringValue': null,
      'boolValue': true,
      'dateValue': null,
      'numberValue': null,
    },
    {
      'id': 'cccccccc-0000-0000-0000-000000000002',
      'reportId': '11111111-1111-1111-1111-111111111111',
      'ticketControlId': '88888888-8888-8888-8888-888888888888',
      'stringValue': null,
      'boolValue': null,
      'dateValue': null,
      'numberValue': 4.2,
    },
  ],
  'allegati': <dynamic>[],
  'laborCostTotal': null,
};

void main() {
  test('parses the header from the backend projection', () {
    final r = ServerReportDto.fromJson(backendFixture());
    expect(r.id, '11111111-1111-1111-1111-111111111111');
    expect(r.tenantId, '22222222-2222-2222-2222-222222222222');
    expect(r.title, 'Sostituzione pompa');
    expect(r.ticketId, '33333333-3333-3333-3333-333333333333');
    expect(r.customerId, '44444444-4444-4444-4444-444444444444');
    expect(r.locationId, '66666666-6666-6666-6666-666666666666');
    expect(r.insertedUserId, '55555555-5555-5555-5555-555555555555');
    expect(r.details, 'Sostituita pompa; verificata tenuta');
    expect(r.diagnosi, 'Pompa bloccata');
    expect(r.soluzione, 'Sostituita');
    expect(r.customerSignoffText, 'Lavoro accettato');
    expect(r.isBozza, isTrue);
  });

  test('parses staff, materiali and observations (controlli)', () {
    final r = ServerReportDto.fromJson(backendFixture());
    expect(r.staff.single.userId, '55555555-5555-5555-5555-555555555555');
    expect(r.staff.single.hoursWorked, 3.5);
    expect(r.staff.single.kmTraveled, 12);
    expect(r.staff.single.vehicle, 'Furgone');
    expect(r.staff.single.pauseMinutes, 15);
    expect(r.staff.single.startTime, DateTime.utc(2026, 10, 1, 7));

    expect(r.materiali, hasLength(2));
    expect(r.materiali[0].materialeId, '77777777-7777-7777-7777-777777777777');
    expect(r.materiali[0].quantity, 2.5);
    expect(r.materiali[0].unitPrice, 10.0);
    expect(r.materiali[1].freeTextName, 'Guarnizione');
    expect(r.materiali[1].quantity, 1.0);

    expect(r.observations, hasLength(2));
    expect(r.observations[0].ticketControlId, '99999999-9999-9999-9999-999999999999');
    expect(r.observations[0].boolValue, isTrue);
    expect(r.observations[1].numberValue, 4.2);
  });

  test('stato: int 0 is Bozza, any other int is not; a name is accepted too', () {
    expect(ServerReportDto.fromJson({...backendFixture(), 'stato': 0}).isBozza, isTrue);
    expect(ServerReportDto.fromJson({...backendFixture(), 'stato': 1}).isBozza, isFalse);
    expect(ServerReportDto.fromJson({...backendFixture(), 'stato': 'Bozza'}).isBozza, isTrue);
    expect(ServerReportDto.fromJson({...backendFixture(), 'stato': 'Inviato'}).isBozza, isFalse);
  });

  test('missing child arrays parse as empty, null diagnosi/soluzione stay null', () {
    final j = backendFixture()
      ..remove('staff')
      ..remove('materiali')
      ..remove('observations')
      ..['diagnosi'] = null
      ..['soluzione'] = null;
    final r = ServerReportDto.fromJson(j);
    expect(r.staff, isEmpty);
    expect(r.materiali, isEmpty);
    expect(r.observations, isEmpty);
    expect(r.diagnosi, isNull);
    expect(r.soluzione, isNull);
  });
}
