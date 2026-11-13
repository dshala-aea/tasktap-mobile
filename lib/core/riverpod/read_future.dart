import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

/// Reads a provider's future while keeping an autoDispose provider alive until it resolves.
///
/// Riverpod 3 pauses/disposes a provider as soon as it has no listeners. A bare
/// `ref.readFuture(provider.future)` is not a listener, so an autoDispose provider can be disposed while
/// its future is still loading. The temporary listener keeps the provider alive for exactly the
/// duration of the read, then releases it.
extension ReadFutureOnWidgetRef on WidgetRef {
  Future<T> readFuture<T>(ProviderListenable<Future<T>> provider) async {
    final subscription = listenManual(provider, (_, _) {});
    try {
      return await read(provider);
    } finally {
      subscription.close();
    }
  }
}

extension ReadFutureOnRef on Ref {
  Future<T> readFuture<T>(ProviderListenable<Future<T>> provider) async {
    // Ref.listen has no manual subscription in Riverpod 3; the listener lives with the provider
    // and is removed when the provider is disposed.
    listen(provider, (_, _) {});
    return read(provider);
  }
}
