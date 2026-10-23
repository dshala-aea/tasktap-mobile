// dart format width=100
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sync_service.dart' show appDatabaseProvider;

/// Whether this device has ever completed a sync.
///
/// An empty mirror is only a fact about the tenant once a payload has landed on this phone. On a
/// fresh install — or a device that has been offline since it was set up — every table is empty
/// for a reason that has nothing to do with the tenant, and a list that answers "non c'è niente"
/// from that emptiness is stating something it cannot know. Callers pair this with their own
/// empty list to choose between "genuinely nothing" and "not downloaded yet".
///
/// A stream, not a one-shot read: a sync completing while a screen is open has to flip the
/// answer, which is the entire point of the distinction. Null means the query has not answered
/// yet — callers must treat that as "don't change what you were going to say" rather than as
/// "never synced", or the first frame of every screen would accuse the device of having no data.
final hasSyncedAtLeastOnceProvider = StreamProvider.autoDispose<bool>((ref) {
  return ref.watch(appDatabaseProvider).watchLastSync().map((lastSync) => lastSync != null);
});
