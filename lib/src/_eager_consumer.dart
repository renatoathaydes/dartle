import 'dart:async';

/// A [StreamConsumer] that eagerly consumes data, pushing it into an internal
/// [List], which can be accessed only once all elements of the delegate
/// [Stream] have been consumed.
class EagerConsumer<T> with StreamConsumer<T> {
  final _done = Completer();
  final _all = <T>[];
  var _delegateAdded = false;

  /// Whether the sink has been closed.
  var _closed = false;

  /// The consumed data, once all elements of the delegate [Stream] have been
  /// consumed.
  Future<List<T>> get consumedData async {
    await _done;
    return _all;
  }

  void add(T data) {
    _checkEventAllowed();
    _all.add(data);
  }

  void addError(error, [StackTrace stackTrace]) {
    _checkEventAllowed();
    _done.completeError(error, stackTrace);
  }

  @override
  Future addStream(Stream<T> stream) async {
    _checkEventAllowed();
    if (_delegateAdded) {
      throw StateError("Cannot add stream, it was already added.");
    }
    _delegateAdded = true;
    await for (final data in stream) {
      add(data);
    }
    _done.complete(null);
  }

  /// Throws a [StateError] if [close] has been called.
  void _checkEventAllowed() {
    if (_closed) throw StateError("Cannot add to a closed sink.");
  }

  @override
  Future close() {
    _closed = true;
    return _done.future;
  }
}
