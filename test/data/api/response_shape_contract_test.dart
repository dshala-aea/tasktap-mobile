import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/api/json_parse.dart';

/// Every `_dio.get<T>()` in the app, checked against the frozen backend contract.
///
/// Six call sites asked Dio for `List<dynamic>` from routes that return a `PaginatedResultOf<T>`
/// envelope. Dio casts the decoded body to `T`, so each one threw at runtime and emptied its
/// screen — including both technician pickers, which is why no technician could be assigned to a
/// ticket at all. Nothing caught it: the type is a generic argument, so the analyzer is satisfied,
/// and no test exercised a real response body.
///
/// The snapshot at `../docs/api/openapi.snapshot.json` is the same artifact the maintenance-
/// controls gate uses. This walks it rather than trusting a hand-kept list.
void main() {
  final specFile = File('../docs/api/openapi.snapshot.json');

  test('no client asks for a response shape the backend does not return', () {
    if (!specFile.existsSync()) {
      markTestSkipped('openapi.snapshot.json not reachable from this checkout');
      return;
    }

    final spec = jsonDecode(specFile.readAsStringSync()) as Map<String, dynamic>;
    final paths = spec['paths'] as Map<String, dynamic>;
    final schemas = (spec['components'] as Map<String, dynamic>)['schemas'] as Map<String, dynamic>;

    /// 'Map', 'List', or null when the route documents no JSON body.
    String? serverShape(String route, String method) {
      final op = (paths[route] as Map<String, dynamic>?)?[method] as Map<String, dynamic>?;
      if (op == null) return null;
      for (final code in ['200', '201']) {
        final schema =
            (((op['responses'] as Map<String, dynamic>?)?[code]
                        as Map<String, dynamic>?)?['content']
                    as Map<String, dynamic>?)?['application/json']
                as Map<String, dynamic>?;
        final s = schema?['schema'] as Map<String, dynamic>?;
        if (s == null) continue;
        if (s['type'] == 'array') return 'List';
        final ref = s[r'$ref'] as String?;
        if (ref != null) {
          final named = schemas[ref.split('/').last] as Map<String, dynamic>?;
          return named?['type'] == 'array' ? 'List' : 'Map';
        }
        if (s['type'] == 'object') return 'Map';
      }
      return null;
    }

    /// Interpolations become wildcards, then segment-for-segment, case-insensitive.
    String? matchRoute(String clientPath) {
      final cleaned = clientPath
          .replaceAll(RegExp(r'\$\{[^}]*\}'), '{p}')
          .replaceAll(RegExp(r'\$[A-Za-z_][A-Za-z0-9_]*'), '{p}');
      final want = cleaned.split('/').where((s) => s.isNotEmpty).toList();

      for (final route in paths.keys) {
        final have = route.split('/').where((s) => s.isNotEmpty).toList();
        if (have.length != want.length) continue;
        var ok = true;
        for (var i = 0; i < have.length; i++) {
          if (have[i].startsWith('{') || want[i] == '{p}') continue;
          if (have[i].toLowerCase() != want[i].toLowerCase()) {
            ok = false;
            break;
          }
        }
        if (ok) return route;
      }
      return null;
    }

    final call = RegExp(
      r"_?dio\.(get|post|put|delete)<\s*(Map<String, dynamic>|List<dynamic>)\s*>\(\s*'([^']+)'",
      multiLine: true,
    );

    final mismatches = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final m in call.allMatches(source)) {
        final method = m.group(1)!;
        final wants = m.group(2)!.startsWith('Map') ? 'Map' : 'List';
        final path = m.group(3)!;

        final route = matchRoute(path);
        if (route == null) continue; // route-existence is a different audit
        final serves = serverShape(route, method);
        if (serves == null) continue; // undocumented body; nothing to compare
        if (serves != wants) {
          mismatches.add(
            '${entity.path.replaceAll(r'\', '/')}: '
            '${method.toUpperCase()} $path expects $wants, backend returns $serves',
          );
        }
      }
    }

    expect(
      mismatches,
      isEmpty,
      reason:
          'Dio casts the decoded body to the generic argument, so a wrong shape throws at '
          'runtime and empties the screen. For a paginated route ask for '
          'Map<String, dynamic> and unwrap with pagedItems().',
    );
  });

  group('pagedItems', () {
    test('unwraps a paginated envelope', () {
      final rows = pagedItems({
        'items': [
          {'id': 'u1'},
          {'id': 'u2'},
        ],
        'page': 1,
        'pageSize': 50,
        'totalItems': 2,
        'totalPages': 1,
      });

      expect(rows, hasLength(2));
      expect(rows.first['id'], 'u1');
    });

    test('accepts a bare array, since not every route paginates', () {
      expect(
        pagedItems([
          {'id': 'a'},
        ]),
        hasLength(1),
      );
    });

    test('an envelope with no items yields nothing rather than throwing', () {
      expect(pagedItems({'page': 1, 'totalItems': 0}), isEmpty);
      expect(pagedItems(null), isEmpty);
      // The shape that used to crash the picker: a Map where a List was demanded.
      expect(pagedItems({'items': null}), isEmpty);
    });
  });
}
