import 'dart:async';
import 'dart:io';

import '_log.dart';

/// Fail the build for the given [reason].
///
/// This function never returns.
failBuild({String reason, int exitCode = 1}) {
  logger.error(reason);
  exit(exitCode);
}

/// Run the given action ignoring any Exceptions thrown by it.
ignoreExceptions(Function() action) async {
  try {
    await action();
  } on Exception {
    // ignore
  }
}

/// Executes the given process.
///
/// Fails the build if the exit value is not 0.
///
/// The [Process]'s streams are always consumed, but only shown to the user
/// if the selected [LogLevel] is [LogLevel.debug] or finer.
///
/// In case of an error, the [Process]'s stderr is shown.
Future<void> exec(Future<Process> process) async {
  final proc = await process;
  logger.debug("Started process: ${proc.pid}");
  final out = _EagerConsumer<List<int>>();
  final err = _EagerConsumer<List<int>>();

  if (logger.isLevelEnabled(LogLevel.debug)) {
    await stdout.addStream(proc.stdout);
  } else {
    await out.addStream(proc.stdout);
  }

  await err.addStream(proc.stderr);

  final code = await proc.exitCode;

  logger.debug("Process ${proc.pid} exited with code: $code");

  if (code != 0) {
    await stderr.addStream(Stream.fromIterable(await err.consumedData));
    failBuild(
        reason: 'Process exited with code $code: ${proc.pid}', exitCode: code);
  }
}

class _EagerConsumer<T> with StreamConsumer<T> {
  final _done = Completer();
  final _all = <T>[];
  var _delegateAdded = false;

  /// Whether the sink has been closed.
  var _closed = false;

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

  /// Throws a [StateError] if [close] has been called or an [addStream] call is
  /// pending.
  void _checkEventAllowed() {
    if (_closed) throw StateError("Cannot add to a closed sink.");
  }

  Future close() {
    _closed = true;
    return _done.future;
  }
}
