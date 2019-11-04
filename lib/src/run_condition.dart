import 'dart:async';

import 'package:meta/meta.dart';

import '_log.dart';
import 'cache.dart';
import 'error.dart';
import 'file_collection.dart';
import 'task_run.dart';

/// A run condition for a [Task].
///
/// A [Task] should not run if its [RunCondition] does not allow it.
mixin RunCondition {
  /// Check if this task should run.
  ///
  /// Returns true if it should, false otherwise.
  FutureOr<bool> shouldRun();

  /// Action to run after a task associated with this [RunCondition]
  /// has run, whether successfully or not.
  FutureOr<void> postRun(TaskResult result);
}

/// A [RunCondition] which is always fullfilled.
///
/// This ensures a [Task] runs unconditionally.
@sealed
class AlwaysRun with RunCondition {
  const AlwaysRun();

  @override
  FutureOr<void> postRun(TaskResult result) {}

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

  /// Creates an instance of [RunOnChanges].
  ///
  /// At least one of [inputs] and [outputs] must be non-empty. For cases where
  /// a task has no inputs or outputs, use [AlwaysRun] instead.
  RunOnChanges(
      {this.inputs = FileCollection.empty,
      this.outputs = FileCollection.empty,
      this.verifyOutputsExist = true,
      DartleCache cache})
      : this.cache = cache ?? DartleCache.instance;

  @override
  FutureOr<bool> shouldRun() async {
    final inputsChanged = await cache.hasChanged(inputs);
    final outputsChanged = await cache.hasChanged(outputs);

    if (inputsChanged) {
      logger.debug('Changes detected on task inputs: ${inputs}');
    }
    if (outputsChanged) {
      logger.debug('Changes detected on task outputs: ${outputs}');
    }
    return inputsChanged || outputsChanged;
  }

  @override
  Future<void> postRun(TaskResult result) async {
    var success = result.isSuccess;
    DartleException error;

    if (success) {
      if (await outputs.isNotEmpty && verifyOutputsExist) {
        logger.debug('Verifying task produced expected outputs');
        try {
          await _verifyOutputs();
        } on DartleException catch (e) {
          success = false;
          error = e;
        }
      }
    }

    if (success) {
      await cache(inputs);
      await cache(outputs);
    } else {
      if (await outputs.isEmpty) {
        // the task failed without any outputs, so for it to run again next
        // time we need to remove its inputs
        await cache.remove(inputs);
      } else {
        // just forget the outputs of the failed task as they
        // may not be correct anymore
        await cache.remove(outputs);
      }
      if (error != null) throw error;
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
