// ══════════════════════════════════════════════════════════════════════════════
// Badge models
//
// Wire shapes of the worker badge backend (tasktap-api PR #181):
//   BadgeCard         — GET  /api/badge/me
//   BadgeScanOutcome  — POST /api/cantieri/{cantiereId}/badge-scan
//
// BadgeScanResult / BadgeScanAction arrive as member NAMES ("Accepted", "Opened"), not integers
// (see the snapshot's BadgeScanResult / BadgeScanAction enums). Both parse case-insensitively and
// map null or any name this build does not know to `unknown`, so a server that appends a member
// can never crash the scanner or read as a success.
// ══════════════════════════════════════════════════════════════════════════════

/// Outcome of a leader scanning a worker badge. Append-only on the server.
enum BadgeScanResult {
  accepted,
  notAssigned,
  revoked,
  expired,
  invalid,
  openElsewhere,
  payrollLocked,
  replayed,

  /// Client-side only: null or a name this build does not recognise.
  unknown;

  static BadgeScanResult fromWire(String? v) {
    if (v == null) return BadgeScanResult.unknown;
    final wanted = v.toLowerCase();
    for (final r in BadgeScanResult.values) {
      if (r != BadgeScanResult.unknown && r.name.toLowerCase() == wanted) return r;
    }
    return BadgeScanResult.unknown;
  }
}

/// What an accepted scan did to the worker's cantiere session.
enum BadgeScanAction {
  none,
  opened,
  closed,

  /// Client-side only: null or a name this build does not recognise.
  unknown;

  static BadgeScanAction fromWire(String? v) {
    if (v == null) return BadgeScanAction.unknown;
    final wanted = v.toLowerCase();
    for (final a in BadgeScanAction.values) {
      if (a != BadgeScanAction.unknown && a.name.toLowerCase() == wanted) return a;
    }
    return BadgeScanAction.unknown;
  }
}

/// What the worker's phone renders: identity, employer and a fresh rotating token.
///
/// [token] is the QR payload. Never log it, persist it or put it in a URL.
class BadgeCard {
  const BadgeCard({
    required this.badgeId,
    required this.token,
    required this.expiresInSeconds,
    required this.displayName,
    this.photoUrl,
    required this.employerName,
    required this.status,
  });

  final String badgeId;
  final String token;
  final int expiresInSeconds;
  final String displayName;
  final String? photoUrl;
  final String employerName;
  final String status;

  factory BadgeCard.fromJson(Map<String, dynamic> json) => BadgeCard(
    badgeId: json['badgeId'] as String,
    token: json['token'] as String,
    // The snapshot allows an integer or a numeric string for int32.
    expiresInSeconds: _asInt(json['expiresInSeconds']),
    displayName: json['displayName'] as String,
    photoUrl: json['photoUrl'] as String?,
    employerName: json['employerName'] as String,
    status: json['status'] as String,
  );
}

/// The worker a scan resolved to (null on the outcome when the token identified nobody).
class BadgeWorker {
  const BadgeWorker({required this.displayName, this.photoUrl, required this.employerName});

  final String displayName;
  final String? photoUrl;
  final String employerName;

  factory BadgeWorker.fromJson(Map<String, dynamic> json) => BadgeWorker(
    displayName: json['displayName'] as String,
    photoUrl: json['photoUrl'] as String?,
    employerName: json['employerName'] as String,
  );
}

/// The recorded result of one scan. Every result is HTTP 200; the leader needs the reason.
class BadgeScanOutcome {
  const BadgeScanOutcome({
    required this.result,
    required this.action,
    this.workLogId,
    this.worker,
  });

  final BadgeScanResult result;
  final BadgeScanAction action;
  final String? workLogId;
  final BadgeWorker? worker;

  factory BadgeScanOutcome.fromJson(Map<String, dynamic> json) {
    final w = json['worker'];
    return BadgeScanOutcome(
      result: BadgeScanResult.fromWire(json['result'] as String?),
      action: BadgeScanAction.fromWire(json['action'] as String?),
      workLogId: json['workLogId'] as String?,
      worker: w is Map<String, dynamic> ? BadgeWorker.fromJson(w) : null,
    );
  }
}

int _asInt(Object? v) => v is int ? v : int.parse(v.toString());
