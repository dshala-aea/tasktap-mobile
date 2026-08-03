// Prints every HTTP path literal used by the app's api clients, one per line,
// as "<file>:<line>\t<method>\t<path>". Run:
//   dart run tool/extract_routes.dart > /tmp/mobile-routes.txt
//
// This walks lib/**/*.dart looking for Dio calls: `.get(...)`, `.post(...)`,
// `.put(...)`, `.patch(...)`, `.delete(...)`, `.head(...)`, and
// `.request(..., options: Options(method: 'X'))`.
//
// Design notes / deliberate scope (see "Known limitations" below):
//
// 1. Whole-file scan, not line-by-line. Nearly every call site in this
//    codebase wraps its argument list onto the next line, e.g.:
//        final res = await _dio.post<Map<String, dynamic>>(
//          '/api/customers',
//          ...
//        );
//    A naive per-line regex (open paren on one line, string literal on the
//    next) never matches this — it would silently miss almost every route
//    in lib/features/admin/admin_api_client.dart and friends. We read each
//    file as one string and let `\s` (which matches newlines in Dart RegExp)
//    span the line break between the verb and the path literal.
//
// 2. Interpolated path segments. Two shapes appear in this codebase:
//      '/tickets/$id'                       (bare identifier interpolation)
//      '/api/devices/${device['id']}'       (braced expression, itself
//                                             containing a single-quoted
//                                             string literal)
//    A plain `[^']+` capture group breaks on shape 2 — it stops at the
//    first quote *inside* the interpolation. The path-body pattern below
//    treats `${...}` as an opaque unit (matched up to the first unescaped
//    `}`, tolerating nested quotes/brackets inside) so the whole literal is
//    captured intact.
//
// 3. Path built from a referenced constant instead of an inline literal,
//    e.g.:
//        static const _path = '/api/sync/mobile';
//        ...
//        await dio.get<...>(_path, ...);
//    When the first argument is a bare lowerCamelCase/_lowerCamelCase
//    identifier (not a string literal), we look for a
//    `const ... <ident> = '<value>';` declaration anywhere in the same file
//    and substitute its value. This resolves `sync_service.dart`'s `_path`
//    constant, the one instance of this pattern found in lib/.
//
// 4. `dio.request(path, options: Options(method: 'POST'))` — the HTTP verb
//    lives in the `options:` argument, not in the method name. Handled by a
//    second pass over the same call sites.
//
// Known limitations (deliberately left unmatched — see task-4-report.md):
//   - String concatenation to build a path (`'/api/' + segment`) is not
//     handled. None was found in lib/ as of this run (verified by manually
//     auditing every file that references `_dio`/`dio`/`ApiClient`), but a
//     future call site built this way would not be printed, and would not
//     error either — it would simply be silently absent from the report.
//   - Constant resolution only looks within the *same file* as the call
//     site (single-hop, single-file). A constant imported from another
//     file would not be resolved and the call site would be skipped with a
//     warning on stderr.
//   - Only `dio`/`_dio`-style receivers are scanned; this intentionally
//     matches Drift query methods too (`.get()`, `.delete()`) as raw
//     candidates, but those never carry a string-literal first argument so
//     they never produce a false-positive route row.
import 'dart:io';

/// One `${...}` interpolation, tolerant of nested quotes/brackets inside
/// (e.g. `${device['id']}`), matched non-greedily up to the first `}`.
const _bracedInterp = r"\$\{[^}]*\}";

/// One `$identifier` interpolation.
const _bareInterp = r"\$[A-Za-z_][A-Za-z0-9_]*";

/// Body of a single-quoted path string: any run of non-quote/non-`$`
/// characters, or one of the two interpolation shapes above, repeated.
const _pathBody = "(?:[^'\$]|$_bracedInterp|$_bareInterp)*";

/// A quoted path literal, OR a bare identifier (candidate constant
/// reference) — capture group 2 is the literal text (with quotes stripped
/// mentally by the outer group boundaries), group 3 is a bare identifier.
const _argument = "(?:'($_pathBody)'|([A-Za-z_][A-Za-z0-9_]*))";

/// An optional Dart generic type argument list, tolerant of one level of
/// nesting — e.g. `<Map<String, dynamic>>` or `<List<dynamic>>`, both of
/// which are the common shape in this codebase's Dio call sites. A naive
/// `<[^>]*>` stops at the *first* `>` (the inner type's closing bracket),
/// leaving a stray `>` before the call's `(` and failing the whole match —
/// this was caught by manually cross-checking the extractor's first output
/// against a hand audit of every api-client file, which turned up dozens of
/// silently-dropped call sites, all using nested generics.
const _genericArgs = r"(?:<(?:[^<>]|<[^<>]*>)*>)?";

/// `.get(...)`, `.post(...)`, etc., optionally with a generic type argument,
/// followed (possibly after a line break) by the path argument.
final _call = RegExp(
  r"\.(get|post|put|patch|delete|head)" + _genericArgs + r"\s*\(\s*" + _argument,
);

/// `.request(...)` — verb is separate, read from `method: 'X'` nearby.
final _requestCall = RegExp(
  r"\.request" + _genericArgs + r"\s*\(\s*" + _argument,
);

/// `method: 'POST'` (or similar) inside an Options(...) that follows a
/// `.request(` call. Searched only in a bounded window after the call so it
/// doesn't accidentally bind to an unrelated later `method:` in the file.
final _methodOption = RegExp(r"""method\s*:\s*'([A-Za-z]+)'""");

/// `const <Type>? <ident> = '<value>';` — used to resolve path constants
/// referenced by identifier instead of by literal (e.g. sync_service.dart's
/// `_path`).
final _constDecl = RegExp(
  r"""const\s+(?:[\w<>?, ]+\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*'([^']*)'""",
);

class RouteHit {
  RouteHit(this.file, this.line, this.method, this.path);
  final String file;
  final int line;
  final String method;
  final String path;
}

void main() {
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final hits = <RouteHit>[];
  final warnings = <String>[];

  for (final file in files) {
    final content = file.readAsStringSync();
    final consts = _collectConsts(content);

    for (final m in _call.allMatches(content)) {
      final method = m.group(1)!.toUpperCase();
      // Group 1 is the verb; the argument groups are 2 (literal) and 3 (ident).
      final resolved =
          _resolveArg(m, 2, 3, consts, file.path, m.start, warnings);
      if (resolved == null) continue;
      final line = _lineOf(content, m.start);
      hits.add(RouteHit(file.path, line, method, resolved));
    }

    for (final m in _requestCall.allMatches(content)) {
      // No verb capture group here, so the argument groups shift to 1/2.
      final resolved =
          _resolveArg(m, 1, 2, consts, file.path, m.start, warnings);
      if (resolved == null) continue;
      // Look for `method: '...'` within the next 300 chars (covers the
      // Options(...) argument in every call site we found).
      final windowEnd = (m.end + 300).clamp(0, content.length);
      final window = content.substring(m.end, windowEnd);
      final methodMatch = _methodOption.firstMatch(window);
      final method = methodMatch != null
          ? methodMatch.group(1)!.toUpperCase()
          : 'REQUEST(method unresolved)';
      final line = _lineOf(content, m.start);
      hits.add(RouteHit(file.path, line, method, resolved));
    }
  }

  hits.sort((a, b) {
    final byPath = a.path.compareTo(b.path);
    if (byPath != 0) return byPath;
    final byMethod = a.method.compareTo(b.method);
    if (byMethod != 0) return byMethod;
    final byFile = a.file.compareTo(b.file);
    if (byFile != 0) return byFile;
    return a.line.compareTo(b.line);
  });

  for (final h in hits) {
    stdout.writeln('${h.file}:${h.line}\t${h.method}\t${h.path}');
  }

  for (final w in warnings) {
    stderr.writeln('WARN: $w');
  }
}

/// Collects `const ident = 'value'` declarations in [content] as a map from
/// identifier to string value.
Map<String, String> _collectConsts(String content) {
  final map = <String, String>{};
  for (final m in _constDecl.allMatches(content)) {
    map[m.group(1)!] = m.group(2)!;
  }
  return map;
}

/// Resolves the argument captured by [m] (either group 1 = literal text, or
/// group 2 = bare identifier) to a path string, using [consts] for
/// identifier lookups. Returns null (and appends to [warnings]) if an
/// identifier can't be resolved.
String? _resolveArg(
  RegExpMatch m,
  int literalGroup,
  int identGroup,
  Map<String, String> consts,
  String filePath,
  int matchStart,
  List<String> warnings,
) {
  final literal = m.group(literalGroup);
  if (literal != null) return literal;

  final ident = m.group(identGroup);
  if (ident == null) return null;

  final resolved = consts[ident];
  if (resolved == null) {
    warnings.add(
      '$filePath: call with non-literal, non-resolvable first argument '
      '`$ident` (not a local const) — skipped, not printed as a route.',
    );
    return null;
  }
  return resolved;
}

int _lineOf(String content, int offset) {
  var line = 1;
  for (var i = 0; i < offset; i++) {
    if (content.codeUnitAt(i) == 0x0A) line++;
  }
  return line;
}
