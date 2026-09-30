// dart format width=100
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A user-visible message raised by the background timbratura sync (a dropped or refused tap).
/// HomeShell listens and shows it as a toast. [seq] makes two identical messages distinct events.
class TimbraNotice {
  const TimbraNotice(this.message, this.seq);
  final String message;
  final int seq;
}

final timbraNoticeProvider = StateProvider<TimbraNotice?>((ref) => null);
