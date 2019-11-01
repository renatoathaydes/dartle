import 'dart:async';

import 'package:meta/meta.dart';

import '_log.dart';
import 'cache.dart';
import 'error.dart';
import 'file_collection.dart';

final _functionNamePatttern = RegExp('[a-zA-Z_0-9]+');

/// A Dartle task whose action is provided by user code in order to execute
/// some logic during a build run.
class Task {
  final String name;
  final String description;
  final Function() action;
  final RunCondition runCondition;

  Task(
    this.action, {
    this.description = '',
    String name = '',
    this.runCondition = const AlwaysRun(),
  }) : this.name = _resolveName(action, name ?? '');

  static String _resolveName(Function() action, String name) {
    if (name.isEmpty) {
      final funName = "$action";
      final firstQuote = funName.indexOf("'");
      if (firstQuote > 0) {
        final match =
            _functionNamePatttern.firstMatch(funName.substring(firstQuote + 1));
        if (match != null) {
          String inferredName = match.group(0);
          // likely generated from JS lambda if it looks like 'main___closure',
          // do not accept it
          if (!inferredName.contains('___')) {
            return inferredName;
          }
        }
      }

      throw ArgumentError('Task name cannot be inferred. Either give the task '
          'a name explicitly or use a top-level function as its action');
    }
    return name;
  }

  @override
  String toString() => 'Task{name: $name}';
}

/// A run condition for a [Task].
///
/// A [Task] will not run if its [RunCondition] does not allow it.
mixin RunCondition {
  /// Check if this task should run.
  ///
  /// Returns true if it should, false otherwise.
  FutureOr<bool> shouldRun();

  /// Callback that runs after the task associated with this [RunCondition]
  /// has run, whether successfully or not.
  FutureOr<void> afterRun({@required bool wasSuccessful});
}

/// A [RunCondition] which is always fullfilled.
///
/// This ensures a [Task] runs unconditionally.
@sealed
class AlwaysRun with RunCondition {
  const AlwaysRun();

  @override
  void afterRun({@required bool wasSuccessful}) {}

  @override
  bool shouldRun() => true;
}

/// A [RunCondition] which reports that a task should run whenever its inputs
/// or outputs have changed since the last build.
///
/// If an empty [FileCollection] is given as both inputs and outputs,
/// because an empty collection will never change, [shouldRun] will never
/// return true, hence using this class in this way is likely a mistake.
class RunOnChanges with RunCondition {
  final FileCollection inputs;
  final FileCollection outputs;
  final DartleCache cache;

  /// whether to verify that all declared outputs exist after the task has run.
  final bool verifyOutputsExist;

  RunOnChanges(
      {@required this.inputs,
      @required this.outputs,
      this.verifyOutputsExist = true,
      DartleCache cache})
      : this.cache = cache ?? DartleCache.instance;

  @override
  FutureOr<bool> shouldRun() async {
    final inputsChanged = await cache.hasChanged(inputs, cache: true);

    // don't cache outputs, they will be cached after the task executes
    final outputsChanged = await cache.hasChanged(outputs, cache: false);

    if (inputsChanged) {
      logger.debug('Changes detected on task inputs: ${inputs}');
    }
    if (outputsChanged) {
      logger.debug('Changes detected on task outputs: ${outputs}');
    }
    return inputsChanged || outputsChanged;
  }

  @override
  FutureOr<void> afterRun({@required bool wasSuccessful}) async {
    if (wasSuccessful) {
      if (await outputs.isNotEmpty) {
        logger.debug('Verifying task produced expected outputs');
        if (verifyOutputsExist) await _verifyOutputs();
        await cache(outputs);
      }
    }
  }

  Future<void> _verifyOutputs() async {
    final missingOutputs = <String>[];
    await for (final file in outputs.files) {
      if (!await file.exists()) missingOutputs.add(file.path);
    }
    await for (final dir in outputs.directories) {
      if (!await dir.exists()) missingOutputs.add(dir.path);
    }
    if (missingOutputs.isNotEmpty) {
      throw DartleException(
          message: 'task did not produce the following expected outputs:\n' +
              missingOutputs.map((f) => '  * $f').join('\n'));
    }
  }
}
