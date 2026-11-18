// dart format width=100
/// Splits an assistant reply into stretches that can be sent to the speech gateway one at a time,
/// so the first sentence starts playing while the rest is still being synthesised.
///
/// Markdown decoration is dropped (the reply is rendered as text on screen, but nobody wants
/// "asterisk asterisk" read aloud). Fragments shorter than [minChunk] are merged into the next one:
/// a clip per "Ok." costs a round trip for almost no audio. Anything longer than [maxChunk] is cut
/// at a comma or space, well under the server's own limit.
List<String> splitSpeakable(String text, {int minChunk = 40, int maxChunk = 240}) {
  final cleaned = text
      .replaceAll(RegExp(r'[*_`#>]+'), '')
      .replaceAll(RegExp(r'\s*\n+\s*'), '. ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (cleaned.isEmpty) return const [];

  final sentences = <String>[];
  final pattern = RegExp(r'[^.!?;:]+[.!?;:]*\s*');
  for (final m in pattern.allMatches(cleaned)) {
    final s = m.group(0)!.trim();
    if (s.isNotEmpty) sentences.add(s);
  }

  final merged = <String>[];
  var carry = '';
  for (final s in sentences) {
    carry = carry.isEmpty ? s : '$carry $s';
    if (carry.length >= minChunk) {
      merged.add(carry);
      carry = '';
    }
  }
  if (carry.isNotEmpty) {
    if (merged.isNotEmpty && carry.length < minChunk ~/ 2) {
      merged[merged.length - 1] = '${merged.last} $carry';
    } else {
      merged.add(carry);
    }
  }

  final out = <String>[];
  for (final chunk in merged) {
    var rest = chunk;
    while (rest.length > maxChunk) {
      var cut = rest.lastIndexOf(',', maxChunk);
      if (cut < maxChunk ~/ 2) cut = rest.lastIndexOf(' ', maxChunk);
      if (cut <= 0) cut = maxChunk;
      out.add(rest.substring(0, cut + 1).trim());
      rest = rest.substring(cut + 1).trim();
    }
    if (rest.isNotEmpty) out.add(rest);
  }
  return out;
}
