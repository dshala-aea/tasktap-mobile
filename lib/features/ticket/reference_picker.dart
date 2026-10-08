// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/lookup_field.dart';
import '../../data/reference/reference_option.dart';

/// A picker over one reference entity. Two sources, one list:
///
///  - [localItems], the technician's mirrored scope, shown the instant the picker opens and the
///    only source while offline;
///  - [search], an online query, run 300 ms after typing stops, whose results join the list — and
///    which, by its own contract, has already written them to the mirror before returning.
///
/// The two are merged rather than swapped, and that is deliberate: the server matches `q` with a
/// case-sensitive `Contains`, so a term typed in lower case finds nothing for a row stored with a
/// capital — and a replacing search would delete, mid-keystroke, the one row the technician can see
/// and pick. The underlying [AppLookupField] filters the merged list case-insensitively anyway, so
/// a locally matching row stays visible whatever the server answered.
///
/// The widget knows nothing about either source. It does not import Drift, does not import the
/// search client, and does not decide what a search is — a caller hands both in. That keeps the
/// materialise step out of the render tree, where it would run on every rebuild.
///
/// Deliberately modelled on [TicketMaterialiEditor]'s debounce, which is the existing precedent for
/// "local first, remote behind a timer" in this codebase.
class ReferencePickerField extends StatefulWidget {
  const ReferencePickerField({
    super.key,
    required this.label,
    required this.localItems,
    required this.search,
    required this.onSelected,
    this.selectedId,
    this.initialText,
    this.hint,
    this.emptyCacheHint = 'Nessun elemento in cache. Cerca per nome.',
    this.enabled = true,
  });

  final String label;

  /// The offline candidates, from a provider. Never fetched by this widget.
  final List<ReferenceOption> localItems;

  /// Search then materialise then return. See [ReferenceSearchClient].
  final Future<List<ReferenceOption>> Function(String query) search;

  /// Called with the picked option, or with null when a pick is released by editing the text.
  final ValueChanged<ReferenceOption?> onSelected;

  final String? selectedId;
  final String? initialText;
  final String? hint;

  /// Shown while the field has focus and there is nothing to offer, so "no suggestions" reads as a
  /// sync state rather than as the field being broken.
  final String emptyCacheHint;

  final bool enabled;

  /// The key the underlying lookup field carries, derived from the label so a test — or a golden
  /// path — can address one picker among the several a wizard step holds.
  ValueKey<String> get fieldKey => ValueKey('reference-picker-${label.toLowerCase()}');

  @override
  State<ReferencePickerField> createState() => _ReferencePickerFieldState();
}

class _ReferencePickerFieldState extends State<ReferencePickerField> {
  static const _debounceDelay = Duration(milliseconds: 300);

  /// Six, as [TicketMaterialiEditor] offers — a suggestion list is a shortcut to a known row, not a
  /// browse surface, and everything beyond the first few is reached faster by typing another letter.
  static const _maxSuggestions = 6;

  Timer? _debounce;

  /// Monotonic per search. An answer whose seq is no longer the current one is discarded: without
  /// this, a slow `man` answer lands on top of a fast `manu` one and the technician picks from a
  /// list that no longer belongs to what they typed.
  int _searchSeq = 0;

  /// The last search's rows, in the order the server sent them. Kept when a later search fails, so
  /// the failure leaves the technician with more than the mirror.
  List<ReferenceOption> _results = const [];

  bool _searchFailed = false;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Local rows first, then the search's, deduped by id with the local row winning.
  ///
  /// The local row wins because it is the one the mirror is guaranteed to hold — see the class doc
  /// comment on why a searched row must be materialised before it can be picked.
  List<ReferenceOption> get _merged {
    final byId = <String, ReferenceOption>{for (final o in widget.localItems) o.id: o};
    for (final o in _results) {
      byId.putIfAbsent(o.id, () => o);
    }
    return byId.values.toList(growable: false);
  }

  void _onFreeText(String text) {
    // Editing the text releases a pick. Keeping the old id behind new text is how a ticket ends up
    // filed against the wrong contract — the same reason [AppLookupField] drops its own selection
    // the moment its text changes.
    if (widget.selectedId?.isNotEmpty ?? false) widget.onSelected(null);

    _debounce?.cancel();
    final query = text.trim();
    final seq = ++_searchSeq;
    if (query.isEmpty) {
      if (_results.isNotEmpty || _searchFailed) {
        setState(() {
          _results = const [];
          _searchFailed = false;
        });
      }
      return;
    }
    // Typing is not a search, and neither is a pause of one and a half letters. The timer is armed
    // here rather than fired, and re-armed on every keystroke, so one search runs per burst.
    _debounce = Timer(_debounceDelay, () => _runSearch(query, seq));
  }

  Future<void> _runSearch(String query, int seq) async {
    try {
      final found = await widget.search(query);
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _results = found;
        _searchFailed = false;
      });
    } on Object {
      // Never rethrown into the tree: a search that fails is not something a technician can act on.
      // The mirror is the offline answer, and it is already on screen.
      if (!mounted || seq != _searchSeq) return;
      setState(() => _searchFailed = true);
    }
  }

  void _onSelected(String id) {
    for (final o in _merged) {
      if (o.id == id) {
        widget.onSelected(o);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      for (final o in _merged) LookupItem(id: o.id, name: o.label, subtitle: o.subtitle),
    ];

    Widget field = AppLookupField(
      key: widget.fieldKey,
      label: widget.label,
      hint: widget.hint,
      items: items,
      selectedId: widget.selectedId,
      initialText: widget.initialText,
      onSelected: _onSelected,
      onFreeText: _onFreeText,
      maxSuggestions: _maxSuggestions,
      emptyCacheHint: widget.emptyCacheHint,
    );
    // [AppLookupField] has no disabled state of its own; absorbing the pointers is what makes
    // `enabled: false` mean anything, and it also stops the field from being typed into.
    if (!widget.enabled) field = AbsorbPointer(child: field);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        field,
        if (_searchFailed)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: AppSpacing.xs),
            child: Text(
              'Non in linea — mostrati i risultati salvati',
              style: TextStyle(fontSize: 12, color: context.colors.inkMuted),
            ),
          ),
      ],
    );
  }
}
