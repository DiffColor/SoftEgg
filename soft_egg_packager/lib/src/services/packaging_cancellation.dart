class PackagingCancellationToken {
  final List<void Function()> _callbacks = <void Function()>[];
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() {
    if (_isCancelled) {
      return;
    }
    _isCancelled = true;
    final callbacks = List<void Function()>.from(_callbacks);
    _callbacks.clear();
    for (final callback in callbacks) {
      callback();
    }
  }

  void throwIfCancelled() {
    if (_isCancelled) {
      throw const PackagingCancelledException();
    }
  }

  PackagingCancellationSubscription onCancel(void Function() callback) {
    if (_isCancelled) {
      callback();
      return const PackagingCancellationSubscription._noop();
    }
    _callbacks.add(callback);
    return PackagingCancellationSubscription._(() {
      _callbacks.remove(callback);
    });
  }
}

class PackagingCancellationSubscription {
  const PackagingCancellationSubscription._(this._dispose);

  const PackagingCancellationSubscription._noop() : _dispose = null;

  final void Function()? _dispose;

  void dispose() {
    _dispose?.call();
  }
}

class PackagingCancelledException implements Exception {
  const PackagingCancelledException([this.message = '작업이 중단되었습니다.']);

  final String message;

  @override
  String toString() => message;
}
