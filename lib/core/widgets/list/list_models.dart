import 'package:flutter/widgets.dart';

/// The body a [ListShell] is currently showing.
enum ListShellState {
  /// Groups, rows and (optionally) a summary footer.
  content,

  /// Group/row skeleton bars, no spinner.
  loading,

  /// The whole list cannot be read (no sync, backend down): caller supplies the
  /// `UnavailableState` (with retry) via `ListShell.unavailable`.
  unavailable,
}

/// The semantic tone of a row's status stamp.
///
/// Kept separate from the Italian label because list statuses include strings that are not in
/// `statusFamilyOf` (`Pianificato`, `In scadenza`, `Principale`, …). The tone is the data-level
/// meaning; the label is what a person reads.
enum ListStatusTone { neutral, info, good, warn, bad }

/// One quick-filter chip in the prototype's chip row.
class ListFilterChipData {
  const ListFilterChipData({required this.label, this.id});

  /// Visible, uppercased by the row: `Attivi`, `Sotto scorta`, …
  final String label;

  /// Stable identity for selection. Optional for short, single-facet lists.
  final String? id;
}

/// One tappable row in a [ListGroupData].
///
/// Presentation only: title, meta line, secondary line and status stamp. No provider or network
/// access. Long Italian strings are clamped by `ListDocumentRow` (title 2 lines, meta/secondary 1).
class ListRowData {
  const ListRowData({
    required this.title,
    this.meta,
    this.secondary,
    this.status,
    this.statusTone,
    this.leading,
    this.onTap,
    this.rowKey,
  });

  final String title;

  /// The muted meta line (`Rossi Srl · Milano · 3 operatori`).
  final String? meta;

  /// The third line (`In corso · 08:30–12:30`).
  final String? secondary;

  /// Stamp text (`Attivo`, `In scadenza`, `Bozza`). Rendered by `StatusStamp`, so it always
  /// carries text for screen readers.
  final String? status;

  /// Overrides the stamp family. Defaults to `statusFamilyOf(status)`.
  final ListStatusTone? statusTone;

  /// Optional leading icon/badge slot. Omit for the prototype's text-first row.
  final Widget? leading;

  final VoidCallback? onTap;

  /// Optional key on the row itself, for tests and screen readers.
  final Key? rowKey;
}

/// A group heading plus its rows: `Da seguire oggi` and its count.
class ListGroupData {
  const ListGroupData({this.title, this.count, required this.rows});

  /// Group heading. Null renders a headerless (flat) group: no heading, no rule and no count
  /// spacing, so a flat list does not have to fake a group name.
  final String? title;

  /// Mono count on the right. Null hides the count; ignored when [title] is null.
  final int? count;

  final List<ListRowData> rows;
}

/// The two-part footer line under a list: `8 cantieri attivi | 2 oggi`.
class ListSummaryData {
  const ListSummaryData({required this.left, required this.right});

  final String left;
  final String right;
}
