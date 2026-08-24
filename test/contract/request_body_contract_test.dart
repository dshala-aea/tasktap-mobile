import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/ai/ai_api_client.dart';
import 'package:tasktap_mobile/data/notifications/notification_api_client.dart';
import 'package:tasktap_mobile/data/settings/notification_settings_api_client.dart';
import 'package:tasktap_mobile/data/timbratura/cantiere_worklog_api_client.dart';
import 'package:tasktap_mobile/data/timbratura/worklog_api_client.dart';
import 'package:tasktap_mobile/features/admin/admin_api_client.dart';
import 'package:tasktap_mobile/features/ticket/ticket_api_client.dart';
import 'package:tasktap_mobile/features/ticket/ticket_workflow_api_client.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Request bodies, against the server's own schema
//
// `openapi_contract_test.dart` already guards one payload — `SubmitReportRequest`
// — because that is where the `controlId` / `ticketControlId` break happened. It
// checks a hand-built literal. Thirty-five other write routes had nothing.
//
// This file takes the other approach and drives the **real client methods**
// through a Dio whose adapter records the request and refuses it, so what gets
// checked is what would actually go on the wire, including every key the method
// adds on its way past. A body assembled inline inside an api client cannot
// drift from its test, because there is no second copy of it here.
//
// Three surfaces, all of which have produced a live bug in this app:
//
//   1. **Body keys.** An unknown key is a real break: the server binds its own
//      missing non-nullable field to a default — `Guid.Empty` for an id, which
//      belongs to nothing and fails ownership checks — and answers 200 or 400
//      with nothing naming the field.
//   2. **Query parameter names.** Unchecked until now.
//   3. **`sort` grammar.** The backend reads a leading minus (`-createdAt`), not
//      SQL (`createdAt desc`). Sent the SQL spelling, it misses the allowlist and
//      raises `invalid_sort`, and a technician clocked into a cantiere never saw
//      their running clock. That was guarded on the one client it broke; here it
//      is guarded on every route the app sorts.
//
// And a fourth thing, which is what keeps this file honest: `every write route
// is either covered here or listed as unguarded`. A new POST added to any api
// client fails that test until someone writes a case or states a reason.
//
// **Refreshing:** `cp ../docs/api/openapi.snapshot.json test/contract/openapi.snapshot.json`.
// ══════════════════════════════════════════════════════════════════════════════

/// A GUID-shaped sentinel, so path normalisation can tell an id segment from a
/// route segment without knowing the route.
String _id(int n) => '00000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';

/// Records the request and refuses it.
///
/// Refusing rather than answering is deliberate: thirty methods parse thirty
/// different response shapes, and a canned body that satisfies all of them does
/// not exist. The request has already been captured by the time the failure
/// propagates, which is the only part this file is about.
class _CapturingAdapter implements HttpClientAdapter {
  RequestOptions? last;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    last = options;
    throw const _RequestCaptured();
  }

  @override
  void close({bool force = false}) {}
}

class _RequestCaptured implements Exception {
  const _RequestCaptured();
}

/// What one call put on the wire.
class Sent {
  const Sent({
    required this.method,
    required this.path,
    required this.body,
    required this.query,
  });

  final String method;
  final String path;
  final Map<String, dynamic>? body;
  final Map<String, dynamic> query;
}

void main() {
  late Map<String, dynamic> paths;
  late Map<String, dynamic> schemas;
  late Dio dio;
  late _CapturingAdapter adapter;

  setUpAll(() {
    final file = File('test/contract/openapi.snapshot.json');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'run from the mobile/ root; see the refresh command in this file’s header',
    );
    final doc = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    paths = doc['paths'] as Map<String, dynamic>;
    schemas = (doc['components'] as Map<String, dynamic>)['schemas'] as Map<String, dynamic>;
  });

  setUp(() {
    adapter = _CapturingAdapter();
    dio = Dio(BaseOptions(baseUrl: 'https://contract.test'))..httpClientAdapter = adapter;
  });

  /// Runs [call] and returns what it tried to send.
  ///
  /// Every call is expected to throw — the adapter refuses it — so the throw is
  /// swallowed rather than asserted on. What must not happen is *no request at
  /// all*: a method that returns early leaves `last` null, and a silently
  /// uncovered route is exactly what this file exists to prevent.
  Future<Sent> capture(Future<void> Function() call) async {
    try {
      await call();
    } catch (_) {
      // Expected: the adapter never answers.
    }
    final options = adapter.last;
    expect(options, isNotNull, reason: 'the method returned without issuing a request');
    return Sent(
      method: options!.method.toUpperCase(),
      path: options.path,
      body: options.data is Map<String, dynamic> ? options.data as Map<String, dynamic> : null,
      query: options.queryParameters,
    );
  }

  // ── Snapshot lookup ─────────────────────────────────────────────────────────

  /// A path reduced to what identifies the *route*: lower case, and every id
  /// segment collapsed to `{}`.
  ///
  /// The app spells controller names in lower case (`/api/cantiereworklog/start`)
  /// where the snapshot spells them as declared (`/api/CantiereWorkLog/start`).
  /// ASP.NET routing is case-insensitive so both reach the same action, and a
  /// matcher that was not would report thirty false breaks.
  String normalise(String path) {
    final segments = path.split('/').map((segment) {
      if (segment.startsWith('{') && segment.endsWith('}')) return '{}';
      if (RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(segment)) return '{}';
      if (RegExp(r'^\d+$').hasMatch(segment)) return '{}';
      return segment.toLowerCase();
    });
    return segments.join('/');
  }

  Map<String, dynamic> operationFor(Sent sent) {
    final wanted = normalise(sent.path);
    for (final entry in paths.entries) {
      if (normalise(entry.key) != wanted) continue;
      final ops = entry.value as Map<String, dynamic>;
      final op = ops[sent.method.toLowerCase()];
      if (op is Map<String, dynamic>) return op;
    }
    fail(
      'the app calls ${sent.method} ${sent.path} and the snapshot has no such route. '
      'Either it was renamed on the server, or the snapshot is stale.',
    );
  }

  /// The property names of the request body schema, or null when the route
  /// declares no JSON body or an inline one we cannot resolve.
  Set<String>? bodyPropertiesFor(Map<String, dynamic> op) {
    final content = (op['requestBody'] as Map<String, dynamic>?)?['content'];
    if (content is! Map<String, dynamic>) return null;
    final schema = (content['application/json'] as Map<String, dynamic>?)?['schema'];
    if (schema is! Map<String, dynamic>) return null;

    final ref = schema[r'$ref'];
    final resolved = ref is String
        ? schemas[ref.split('/').last] as Map<String, dynamic>?
        : schema;
    final properties = resolved?['properties'];
    return properties is Map<String, dynamic> ? properties.keys.toSet() : null;
  }

  Set<String> queryParametersFor(Map<String, dynamic> op) {
    final declared = op['parameters'];
    if (declared is! List) return const {};
    return {
      for (final p in declared)
        if (p is Map<String, dynamic> && p['in'] == 'query' && p['name'] is String)
          (p['name'] as String).toLowerCase(),
    };
  }

  // ── The assertion every case runs ───────────────────────────────────────────

  void expectMatchesContract(Sent sent) {
    final op = operationFor(sent);

    final known = bodyPropertiesFor(op);
    final body = sent.body;
    if (known != null && body != null) {
      final unknown = body.keys.where((k) => !known.contains(k)).toList()..sort();
      expect(
        unknown,
        isEmpty,
        reason:
            '${sent.method} ${sent.path} sends $unknown, which the server\'s schema does not '
            'declare. The server ignores them and binds its own fields to defaults — a '
            'non-nullable Guid becomes Guid.Empty, which belongs to nothing. '
            'Known: ${(known.toList()..sort()).join(', ')}',
      );
    }

    final declaredQuery = queryParametersFor(op);
    final undeclared = sent.query.keys
        .where((k) => !declaredQuery.contains(k.toLowerCase()))
        .toList()
      ..sort();
    expect(
      undeclared,
      isEmpty,
      reason:
          '${sent.method} ${sent.path} sends query parameters $undeclared that the route does not '
          'declare. Declared: ${(declaredQuery.toList()..sort()).join(', ')}',
    );

    // The sort grammar, on every route rather than the one that broke. The
    // backend reads a leading minus and treats anything else as a column name,
    // so `createdAt desc` misses the allowlist and raises invalid_sort.
    final sort = sent.query['sort'];
    if (sort is String) {
      expect(
        sort.contains(' '),
        isFalse,
        reason:
            '${sent.path} sorts by "$sort". The backend grammar is a leading minus for descending '
            '(-createdAt), not SQL. A value with a space is read as a column name, misses the '
            'allowlist, and the whole request fails.',
      );
    }
  }

  /// Every write route this file drives. Kept as a set so the coverage test at
  /// the bottom can compare it against what the api clients actually call.
  final covered = <String>{};

  /// The routes where a body schema was actually resolved and compared.
  ///
  /// Tracked because the most likely way this whole file rots is silently: if
  /// path normalisation stops matching, or the snapshot stops carrying `$ref`
  /// schemas, every check turns into a no-op and thirty-nine green tests prove
  /// nothing. This codebase has already shipped one test that asserted a Dart
  /// class against itself; the same shape of mistake at file scale would be
  /// worse, because it looks like coverage.
  final compared = <String>{};

  void contractTest(String description, Future<Sent> Function() run) {
    test(description, () async {
      final sent = await run();
      final key = '${sent.method} ${normalise(sent.path)}';
      covered.add(key);
      if (sent.body != null && bodyPropertiesFor(operationFor(sent)) != null) {
        compared.add(key);
      }
      expectMatchesContract(sent);
    });
  }

  // ── The technician's own write paths ────────────────────────────────────────
  //
  // These come first because they are the ones that lose work when they break:
  // a rejected timbratura is a day of pay, a rejected ticket is a job nobody
  // knows about.

  group('timbratura', () {
    contractTest('the mobile session upsert matches the server', () {
      final client = WorklogApiClient(dio);
      return capture(
        () => client.upsertSessions([
          MobileSessionDto(
            clientId: _id(1),
            startTime: DateTime.utc(2026, 8, 16, 7),
            endTime: DateTime.utc(2026, 8, 16, 16),
            latitude: 45.4642,
            longitude: 9.19,
          ),
        ]),
      );
    });

    contractTest('submitting the day matches the server', () {
      final client = WorklogApiClient(dio);
      return capture(() => client.submitToday());
    });

    contractTest('cantiere clock-in matches the server', () {
      final client = CantiereWorklogApiClient(dio);
      return capture(
        () => client.startCantiere(
          StartCantiereRequest(
            cantiereId: _id(2),
            customerId: _id(3),
            ticketId: _id(4),
            description: 'sostituzione pompa',
            workOrderNumber: 'WO-1',
            equipmentUsed: 'chiave dinamometrica',
            teamSize: 2,
            latitude: 45.4,
            longitude: 9.1,
            arrivalLatitude: 45.4,
            arrivalLongitude: 9.1,
            weatherConditions: 'sereno',
          ),
        ),
      );
    });

    contractTest('cantiere clock-out matches the server', () {
      final client = CantiereWorklogApiClient(dio);
      return capture(
        () => client.endCantiere(
          const EndCantiereRequest(
            description: 'lavoro concluso',
            departureLatitude: 45.4,
            departureLongitude: 9.1,
            safetyNotes: 'nessuna anomalia',
          ),
        ),
      );
    });

    contractTest('the cantiere mobile session upsert matches the server', () {
      final client = CantiereWorklogApiClient(dio);
      return capture(
        () => client.upsertSessions([
          CantiereMobileSessionDto(
            clientId: _id(14),
            cantiereId: _id(15),
            customerId: _id(16),
            ticketId: _id(17),
            description: 'lavoro in corso',
            startTime: DateTime.utc(2026, 8, 16, 7),
            endTime: DateTime.utc(2026, 8, 16, 16),
            latitude: 45.4642,
            longitude: 9.19,
          ),
        ]),
      );
    });
  });

  group('ticket', () {
    contractTest('ticket creation matches the server', () {
      final client = TicketApiClient(dio);
      return capture(
        () => client.createTicket(
          title: 'Perdita in centrale termica',
          description: 'segnalata dal cliente',
          customerId: _id(5),
          locationId: _id(6),
          assignedUserId: _id(7),
          statusId: 1,
          typeId: 1,
          clientId: _id(8),
        ),
      );
    });

    contractTest('a status change matches the server', () {
      final client = TicketWorkflowApiClient(dio);
      return capture(() => client.updateStatus(ticketId: _id(9), statusId: 2));
    });

    contractTest('self-assign matches the server', () {
      final client = TicketWorkflowApiClient(dio);
      return capture(() => client.selfAssign(_id(10)));
    });

    contractTest('starting the ticket timer matches the server', () {
      final client = TicketWorkflowApiClient(dio);
      return capture(() => client.startTimer(_id(11)));
    });

    contractTest('stopping the ticket timer matches the server', () {
      final client = TicketWorkflowApiClient(dio);
      return capture(() => client.stopTimer(_id(12)));
    });

    contractTest('a manually entered worklog matches the server', () {
      final client = TicketWorkflowApiClient(dio);
      return capture(
        () => client.addManual(
          ticketId: _id(13),
          workDate: DateTime.utc(2026, 8, 16),
          start: const Duration(hours: 8),
          end: const Duration(hours: 12),
          description: 'intervento',
        ),
      );
    });
  });

  group('notifications and settings', () {
    contractTest('the notification settings update matches the server', () {
      final client = NotificationSettingsApiClient(dio);
      return capture(
        () => client.update(
          enablePush: true,
          ticketNotifications: true,
          documentNotifications: false,
        ),
      );
    });

    contractTest('marking one notification read matches the server', () {
      final client = NotificationApiClient(dio);
      return capture(() => client.markAsRead(_id(14)));
    });

    contractTest('marking everything read matches the server', () {
      final client = NotificationApiClient(dio);
      return capture(() => client.markAllAsRead());
    });
  });

  group('ai', () {
    contractTest('the draft request matches the server', () {
      final client = AiApiClient(dio);
      return capture(
        () => client.generateDraft(
          scheduleId: _id(15),
          ticketId: _id(16),
          voiceTranscript: 'sostituita la pompa di circolazione',
        ),
      );
    });
  });

  // ── Office writes ───────────────────────────────────────────────────────────
  //
  // Lower stakes for a technician but the same failure mode, and these are the
  // bodies with the most fields — which is where a rename hides best.

  group('admin CRUD', () {
    contractTest('customer creation matches the server', () {
      final client = AdminApiClient(dio);
      return capture(
        () => client.createCustomer(
          companyName: 'Rossi Impianti Srl',
          taxId: 'IT01234567890',
          address: 'Via Roma 1',
          city: 'Milano',
          postalCode: '20100',
          country: 'IT',
          phone: '021234567',
          email: 'info@rossi.it',
          contactPerson: 'Mario Rossi',
        ),
      );
    });

    contractTest('customer update matches the server', () {
      final client = AdminApiClient(dio);
      return capture(() => client.updateCustomer(_id(17), companyName: 'Rossi Impianti Srl'));
    });

    contractTest('location creation matches the server', () {
      final client = AdminApiClient(dio);
      return capture(
        () => client.createLocation(
          customerId: _id(18),
          name: 'Sede centrale',
          address: 'Via Roma 1',
          city: 'Milano',
          postalCode: '20100',
          country: 'IT',
          latitude: 45.4642,
          longitude: 9.19,
        ),
      );
    });

    contractTest('location update matches the server', () {
      final client = AdminApiClient(dio);
      return capture(() => client.updateLocation(_id(19), name: 'Sede centrale'));
    });

    contractTest('cantiere creation matches the server', () {
      final client = AdminApiClient(dio);
      return capture(
        () => client.createCantiere(
          name: 'Cantiere Centro',
          address: 'Via Verdi 2',
          city: 'Milano',
          postalCode: '20100',
          notes: 'accesso da retro',
          startDate: DateTime.utc(2026, 8, 1),
          endDate: DateTime.utc(2026, 12, 1),
          customerId: _id(20),
        ),
      );
    });

    contractTest('cantiere update matches the server', () {
      final client = AdminApiClient(dio);
      return capture(() => client.updateCantiere(_id(21), name: 'Cantiere Centro'));
    });

    contractTest('schedule creation matches the server', () {
      final client = AdminApiClient(dio);
      return capture(
        () => client.createSchedule(
          activityDate: DateTime.utc(2026, 8, 20),
          timeStartMinutes: 480,
          timeEndMinutes: 720,
          userId: _id(22),
          statusId: 1,
          locationId: _id(23),
        ),
      );
    });

    contractTest('schedule update matches the server', () {
      final client = AdminApiClient(dio);
      return capture(() => client.updateSchedule(_id(24), statusId: 2));
    });

    contractTest('ticket assignment matches the server', () {
      final client = AdminApiClient(dio);
      return capture(() => client.assignTicket(_id(25), _id(26)));
    });

    contractTest('materiale creation matches the server', () {
      final client = AdminApiClient(dio);
      return capture(
        () => client.createMateriale(
          code: 'MAT-1',
          name: 'Guarnizione',
          description: 'DN50',
          unitOfMeasure: 'pz',
          category: 'idraulica',
          marca: 'ACME',
          purchasePrice: 1.5,
          salePrice: 3,
        ),
      );
    });

    contractTest('materiale update matches the server', () {
      final client = AdminApiClient(dio);
      return capture(() => client.updateMateriale(_id(27), name: 'Guarnizione'));
    });

    contractTest('prodotto in assistenza creation matches the server', () {
      final client = AdminApiClient(dio);
      return capture(
        () => client.createProdottoAssistenza(
          name: 'Caldaia',
          customerId: _id(28),
          locationId: _id(29),
          description: 'a condensazione',
          serialNumber: 'SN-1',
          warrantyExpiryDate: DateTime.utc(2027, 1, 1),
          notes: 'manutenzione annuale',
        ),
      );
    });

    contractTest('prodotto in assistenza update matches the server', () {
      final client = AdminApiClient(dio);
      return capture(() => client.updateProdottoAssistenza(_id(30), name: 'Caldaia'));
    });

    contractTest('contract creation matches the server', () {
      final client = AdminApiClient(dio);
      return capture(
        () => client.createContract(
          name: 'Manutenzione 2026',
          customerId: _id(31),
          startDate: DateTime.utc(2026, 1, 1),
          description: 'full service',
          locationId: _id(32),
          endDate: DateTime.utc(2026, 12, 31),
        ),
      );
    });

    contractTest('contract update matches the server', () {
      final client = AdminApiClient(dio);
      return capture(() => client.updateContract(_id(33), name: 'Manutenzione 2026'));
    });

    contractTest('squadra creation matches the server', () {
      final client = AdminApiClient(dio);
      return capture(
        () => client.createSquadra(
          nome: 'Squadra Nord',
          descrizione: 'zona nord',
          specializzazione: 'idraulica',
          coloreCalendario: '#FFF10E',
          note: 'due mezzi',
        ),
      );
    });

    contractTest('squadra update matches the server', () {
      final client = AdminApiClient(dio);
      return capture(() => client.updateSquadra(_id(34), nome: 'Squadra Nord'));
    });

    contractTest('adding a squadra member matches the server', () {
      final client = AdminApiClient(dio);
      return capture(() => client.addSquadraMember(_id(35), userId: _id(36)));
    });

    contractTest('marking a report controllato matches the server', () {
      final client = AdminApiClient(dio);
      return capture(() => client.controllaReport(_id(37)));
    });

    contractTest('marking a report fatturato matches the server', () {
      final client = AdminApiClient(dio);
      return capture(() => client.fatturaReport(_id(38)));
    });
  });

  // ── The part that keeps this file honest ────────────────────────────────────

  group('coverage', () {
    /// Write routes that are deliberately not driven here, each with the reason.
    ///
    /// A route belongs in this map only when checking it would prove nothing —
    /// not when writing the case is inconvenient.
    const unguarded = <String, String>{
      'POST /api/reports/submit':
          'covered by openapi_contract_test.dart, which also checks the three nested DTOs',
      'POST /api/reports/{}/attachments':
          'multipart FormData, not a JSON body — there is no schema to check it against',
      'POST /api/devices':
          'sent by NotificationService, which builds its own Dio from Env at call time rather '
          'than taking one, so there is no seam to capture without changing production code',
    };

    /// Proof that the checks above did something.
    ///
    /// A route whose schema cannot be resolved passes `expectMatchesContract`
    /// without comparing a single key. That is the failure mode worth guarding:
    /// a green file that checks nothing reads exactly like a green file that
    /// checks everything.
    ///
    /// The floor is set below the current count on purpose — it is a tripwire
    /// for a systemic break (normalisation, `$ref` resolution, the snapshot
    /// losing its schemas), not a target to keep bumping.
    test('the body checks actually resolved a schema and compared keys', () {
      expect(
        compared.length,
        greaterThanOrEqualTo(15),
        reason:
            'only ${compared.length} route(s) had a resolvable request-body schema, so almost '
            'every check above compared nothing. Path normalisation or \$ref resolution has '
            'broken, or the snapshot no longer carries component schemas. '
            'Compared: ${(compared.toList()..sort()).join(', ')}',
      );
    });

    test('every write route the app calls is covered here or listed as unguarded', () {
      final calls = _writeRoutesInLib();
      // Not `isNotEmpty`. The scanner's first version matched 23 of the app's 36
      // write routes and this test passed anyway, because a scanner that finds
      // less has less to complain about — the failure mode of a coverage check
      // is always that it goes quiet, never that it goes loud.
      expect(
        calls.length,
        greaterThanOrEqualTo(30),
        reason:
            'the scanner found only ${calls.length} write call sites. It has stopped matching a '
            'call shape — check it against `dart run tool/extract_routes.dart` before assuming '
            'the app really lost routes.',
      );

      final exempt = {
        for (final entry in unguarded.keys)
          '${entry.split(' ').first} ${normalise(entry.split(' ').last)}',
      };

      final missing = <String>[];
      for (final call in calls) {
        final key = '${call.method} ${normalise(call.path)}';
        if (covered.contains(key) || exempt.contains(key)) continue;
        missing.add('$key  (${call.origin})');
      }
      missing.sort();

      expect(
        missing,
        isEmpty,
        reason:
            'these write routes send a body that nothing checks against the server\'s schema. '
            'Add a contractTest above, or add it to `unguarded` with the reason it cannot be '
            'checked:\n  ${missing.join('\n  ')}',
      );
    });
  });
}

// ── Scanning lib/ for write call sites ────────────────────────────────────────

class _Call {
  const _Call({required this.method, required this.path, required this.origin});

  final String method;
  final String path;
  final String origin;
}

/// Every POST/PUT/PATCH path literal in the api clients.
///
/// A cut-down `tool/extract_routes.dart` — same whole-file scan, because nearly
/// every call site in this codebase wraps its arguments onto the next line and a
/// per-line regex would silently match almost nothing. Interpolations become
/// `{}` so the result compares against a snapshot path directly.
List<_Call> _writeRoutesInLib() {
  // The type argument is matched as "anything up to the paren", not `[^>]*`.
  // Almost every call here is `.post<Map<String, dynamic>>(`, whose generic
  // contains a `>` of its own — so `[^>]*` stopped at `<Map<String, dynamic>`
  // and matched nothing. That silently hid thirteen of the app's write routes
  // from the coverage test below, which then passed by finding nothing to
  // complain about. A type argument cannot contain an open paren, so this is
  // the safe boundary.
  final pattern = RegExp(
    r'''\.(post|put|patch)(?:<[^(]*>)?\s*\(\s*['"]([^'"]+)['"]''',
    caseSensitive: false,
  );

  final calls = <_Call>[];
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (entity.path.endsWith('.g.dart')) continue;

    final source = entity.readAsStringSync();
    for (final match in pattern.allMatches(source)) {
      final raw = match.group(2)!;
      if (!raw.startsWith('/')) continue;
      calls.add(
        _Call(
          method: match.group(1)!.toUpperCase(),
          // `$id` and `${widget.x}` are route parameters; the snapshot spells
          // them `{id}`, and normalise() reduces both to `{}`.
          path: raw.replaceAll(RegExp(r'\$\{[^}]*\}|\$\w+'), '00000000-0000-0000-0000-000000000000'),
          origin: entity.path.split(Platform.pathSeparator).last,
        ),
      );
    }
  }
  return calls;
}
