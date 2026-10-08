// dart format width=100
import 'dart:convert';

import 'control_type.dart';

/// The value columns of one answer plus its note. Which column matters is decided by the control's
/// type (hand-off 2.2: clients write only the matching column).
class ChecklistAnswer {
  const ChecklistAnswer({this.stringValue, this.boolValue, this.dateValue, this.numberValue, this.note});

  final String? stringValue;
  final bool? boolValue;
  final DateTime? dateValue;
  final double? numberValue;
  final String? note;

  bool get hasNote => (note ?? '').trim().isNotEmpty;

  /// Whether the column that matches [type] holds an answer. A note never does; 0 and false do.
  bool answers(ControlType type) {
    switch (type) {
      case ControlType.text:
      case ControlType.options:
        return (stringValue ?? '').trim().isNotEmpty;
      case ControlType.number:
        return numberValue != null;
      case ControlType.checkbox:
      case ControlType.trueFalse:
        return boolValue != null;
      case ControlType.dateTime:
        return dateValue != null;
      case ControlType.unknown:
        // A type this build does not know: accept whatever column the server filled.
        return (stringValue ?? '').trim().isNotEmpty ||
            boolValue != null ||
            numberValue != null ||
            dateValue != null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ChecklistAnswer &&
      other.stringValue == stringValue &&
      other.boolValue == boolValue &&
      other.dateValue == dateValue &&
      other.numberValue == numberValue &&
      other.note == note;

  @override
  int get hashCode => Object.hash(stringValue, boolValue, dateValue, numberValue, note);
}

class ChecklistControl {
  const ChecklistControl({
    required this.id,
    required this.ticketId,
    this.assetId,
    required this.templateControlId,
    required this.lineageId,
    required this.groupId,
    required this.label,
    this.description,
    required this.type,
    this.isRequired = false,
    this.options,
    this.sortOrder = 0,
    this.status = 'Pending',
    this.stored = const ChecklistAnswer(),
    this.isRetained = false,
  });

  /// The TicketControl id: what `controlli[].ticketControlId` references.
  final String id;
  final String ticketId;

  /// Null for a ticket-level row.
  final String? assetId;
  final String templateControlId;

  /// Version-independent identity (bulk selector; the same control across assets pinned to
  /// different template versions shares it).
  final String lineageId;
  final String groupId;
  final String label;
  final String? description;
  final ControlType type;
  final bool isRequired;
  final String? options;
  final int sortOrder;
  final String status;

  /// What the server currently holds for this row (a previous visit).
  final ChecklistAnswer stored;

  /// The server stopped sending this row but a local Bozza answered it.
  final bool isRetained;

  List<String> get choices {
    final raw = options;
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.map((e) => e.toString()).toList();
    } catch (_) {
      // Not valid JSON: no choices to offer (the field degrades to free text).
    }
    return const [];
  }

  /// Multi-visit rule: the ticket already holds the answer.
  bool get serverHoldsAnswer => status != 'Pending' || stored.answers(type);
}

class ChecklistGroup {
  const ChecklistGroup({
    required this.id,
    required this.name,
    this.sortOrder = 0,
    this.subgroups = const [],
    this.controls = const [],
  });

  final String id;
  final String name;
  final int sortOrder;
  final List<ChecklistGroup> subgroups;
  final List<ChecklistControl> controls;
}

class AssetChecklist {
  AssetChecklist({
    required this.assetId,
    required this.name,
    this.matricola,
    this.templated = false,
    this.legacyControllato = false,
    this.legacyNote,
    this.coveredNow = true,
    this.groups = const [],
  });

  final String assetId;
  final String name;
  final String? matricola;

  /// Has a pinned template version: its answers are checklist rows. False = legacy
  /// Controllato/Note (read-only on the phone).
  final bool templated;
  final bool legacyControllato;
  final String? legacyNote;

  /// False when only retained rows remain (the office removed the asset from the ticket).
  final bool coveredNow;
  final List<ChecklistGroup> groups;

  /// (group path, control) in display order; the path is 'Sezione › Sotto'.
  late final List<(String, ChecklistControl)> placed = _place(groups, '');

  late final List<ChecklistControl> controls = [for (final p in placed) p.$2];

  static List<(String, ChecklistControl)> _place(List<ChecklistGroup> level, String prefix) {
    final out = <(String, ChecklistControl)>[];
    for (final g in level) {
      final path = prefix.isEmpty ? g.name : '$prefix › ${g.name}';
      for (final c in g.controls) {
        out.add((path, c));
      }
      out.addAll(_place(g.subgroups, path));
    }
    return out;
  }
}

class LibrettoGroup {
  const LibrettoGroup({required this.libretto, this.children = const []});

  /// The libretto is itself a covered asset and may carry its own checklist.
  final AssetChecklist libretto;
  final List<AssetChecklist> children;
}

class TicketChecklist {
  const TicketChecklist({
    required this.ticketId,
    this.librettos = const [],
    this.standalone = const [],
    this.omitted = false,
  });

  final String ticketId;
  final List<LibrettoGroup> librettos;
  final List<AssetChecklist> standalone;

  /// The server left this ticket's checklist out of the last sync (5000-row cap).
  final bool omitted;

  /// Every asset once, even when a child sits under two librettos.
  Iterable<AssetChecklist> get distinctAssets sync* {
    final seen = <String>{};
    for (final l in librettos) {
      if (seen.add(l.libretto.assetId)) yield l.libretto;
      for (final c in l.children) {
        if (seen.add(c.assetId)) yield c;
      }
    }
    for (final a in standalone) {
      if (seen.add(a.assetId)) yield a;
    }
  }

  bool get hasAnything => omitted || distinctAssets.isNotEmpty;
}

/// "Caldaia 2" before "Caldaia 10", case-insensitive.
int naturalCompare(String a, String b) {
  final ra = _chunks(a.toLowerCase());
  final rb = _chunks(b.toLowerCase());
  for (var i = 0; i < ra.length && i < rb.length; i++) {
    final x = ra[i];
    final y = rb[i];
    final nx = int.tryParse(x);
    final ny = int.tryParse(y);
    final c = (nx != null && ny != null) ? nx.compareTo(ny) : x.compareTo(y);
    if (c != 0) return c;
  }
  return ra.length.compareTo(rb.length);
}

List<String> _chunks(String s) => RegExp(r'\d+|\D+').allMatches(s).map((m) => m.group(0)!).toList();
