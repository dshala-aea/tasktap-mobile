// dart format width=100
import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../theme/app_palette.dart';
import 'app_text_field.dart';

/// One row in a lookup: something already in the local cache that can be picked by name.
class LookupItem {
  const LookupItem({required this.id, required this.name, this.subtitle});

  final String id;
  final String name;

  /// A second line — an address, a customer, a ticket number. Shown only in the suggestion list.
  final String? subtitle;
}

/// A single field that either resolves to a known record or keeps what was typed.
///
/// The rapportino asked for cliente, ubicazione, ticket and cantiere through a pair of controls
/// each: a dropdown, and a "Non trovo → testo libero" button that swapped it for a plain field
/// with a "Da lista" button to swap back. Four facts, eight controls, and a decision the
/// technician had to make *before* typing anything — which is the wrong order, because whether the
/// customer is in the cache is precisely what they do not know yet.
///
/// This is one field. Type, and matches from the cache appear underneath; tap one and the field
/// holds a real id. Type something with no match and the text stands on its own. Nothing is
/// switched, nothing is lost when the guess about which mode you needed turns out wrong, and
/// clearing a resolved pick just puts the cursor back in the same box.
///
/// Suggestions render inline rather than in an overlay. In a scroll view an overlay has to track
/// the field through scrolling and keyboard insets, and it fails in exactly the conditions this
/// app runs in — a small screen with the keyboard up. Pushing the content down cannot mis-place
/// itself.
class AppLookupField extends StatefulWidget {
  const AppLookupField({
    super.key,
    required this.label,
    required this.items,
    required this.onSelected,
    required this.onFreeText,
    this.hint,
    this.selectedId,
    this.initialText,
    this.maxSuggestions = 6,
    this.emptyCacheHint,
  });

  final String label;
  final String? hint;

  /// Everything the local cache knows. Empty is a normal state, not an error: the field simply
  /// behaves as a plain text input and says so.
  final List<LookupItem> items;

  /// The currently resolved record, if the editor already holds one.
  final String? selectedId;

  /// Free text the editor already holds, used when nothing is resolved.
  final String? initialText;

  final ValueChanged<String> onSelected;

  /// Called with the raw text whenever it is not a resolved pick. Empty string means cleared.
  final ValueChanged<String> onFreeText;

  final int maxSuggestions;

  /// Shown under the field when the cache is empty, so "no suggestions" reads as a sync state
  /// rather than as the field being broken.
  final String? emptyCacheHint;

  @override
  State<AppLookupField> createState() => _AppLookupFieldState();
}

class _AppLookupFieldState extends State<AppLookupField> {
  late final TextEditingController _ctrl;
  late final FocusNode _focus;
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.selectedId?.isNotEmpty == true ? widget.selectedId : null;
    _ctrl = TextEditingController(text: _initialLabel());
    _focus = FocusNode()..addListener(_onFocusChange);
  }

  String _initialLabel() {
    if (_selectedId != null) {
      for (final item in widget.items) {
        if (item.id == _selectedId) return item.name;
      }
    }
    return widget.initialText ?? '';
  }

  @override
  void didUpdateWidget(AppLookupField old) {
    super.didUpdateWidget(old);
    // The cache arrives asynchronously. A field opened on an already-resolved record shows the raw
    // id until the stream lands, so fill in the name the moment it becomes knowable.
    if (_selectedId != null && old.items.length != widget.items.length && _ctrl.text.isEmpty) {
      final name = _initialLabel();
      if (name.isNotEmpty) _ctrl.text = name;
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focus.hasFocus) {
      setState(() {});
      return;
    }
    // Leaving the field: if what was typed names exactly one record, take it. Someone who types a
    // customer's full name and moves on meant that customer, and making them tap the suggestion
    // as well would be a ceremony with no question behind it.
    final typed = _ctrl.text.trim();
    if (_selectedId == null && typed.isNotEmpty) {
      final exact = widget.items.where((i) => i.name.toLowerCase() == typed.toLowerCase());
      if (exact.length == 1) {
        _select(exact.first);
        return;
      }
    }
    setState(() {});
  }

  List<LookupItem> get _suggestions {
    if (_selectedId != null) return const [];
    final q = _ctrl.text.trim().toLowerCase();
    final matches = q.isEmpty
        ? widget.items
        : widget.items.where(
            (i) =>
                i.name.toLowerCase().contains(q) ||
                (i.subtitle?.toLowerCase().contains(q) ?? false),
          );
    return matches.take(widget.maxSuggestions).toList();
  }

  void _select(LookupItem item) {
    setState(() {
      _selectedId = item.id;
      _ctrl.text = item.name;
    });
    _focus.unfocus();
    widget.onSelected(item.id);
  }

  void _clear() {
    setState(() {
      _selectedId = null;
      _ctrl.clear();
    });
    widget.onFreeText('');
    _focus.requestFocus();
  }

  void _onChanged(String v) {
    // Editing a resolved pick releases it — the text is being changed, so it is no longer that
    // record. Silently keeping the old id behind edited text is how a rapportino ends up filed
    // against the wrong customer.
    if (_selectedId != null) _selectedId = null;
    setState(() {});
    widget.onFreeText(v);
  }

  @override
  Widget build(BuildContext context) {
    final resolved = _selectedId != null;
    final suggestions = _focus.hasFocus ? _suggestions : const <LookupItem>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          controller: _ctrl,
          focusNode: _focus,
          label: widget.label,
          hint: widget.hint,
          textInputAction: TextInputAction.next,
          onChanged: _onChanged,
          suffixIcon: _ctrl.text.isEmpty
              ? null
              : IconButton(
                  icon: Icon(
                    resolved ? LucideIcons.check : LucideIcons.x,
                    size: 18,
                    // The tick is the one piece of feedback that distinguishes "this is a real
                    // record" from "this is a note", which is the whole point of the field.
                    color: resolved ? context.colors.green : context.colors.inkMuted,
                  ),
                  onPressed: _clear,
                  tooltip: resolved ? 'Rimuovi collegamento' : 'Cancella',
                  // Full target even though the icon is small — this is used with gloves on.
                  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                ),
        ),
        if (suggestions.isNotEmpty) _SuggestionList(items: suggestions, onTap: _select),
        if (widget.items.isEmpty && widget.emptyCacheHint != null && _focus.hasFocus)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              widget.emptyCacheHint!,
              style: TextStyle(fontSize: 12, color: context.colors.inkMuted),
            ),
          ),
      ],
    );
  }
}

class _SuggestionList extends StatelessWidget {
  const _SuggestionList({required this.items, required this.onTap});

  final List<LookupItem> items;
  final ValueChanged<LookupItem> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.colors.borderLight),
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: context.colors.borderLight),
            InkWell(
              onTap: () => onTap(items[i]),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(i == 0 ? 10 : 0),
                bottom: Radius.circular(i == items.length - 1 ? 10 : 0),
              ),
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      items[i].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.colors.ink,
                      ),
                    ),
                    if (items[i].subtitle?.isNotEmpty ?? false)
                      Text(
                        items[i].subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: context.colors.inkMuted),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
