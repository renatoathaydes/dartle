import 'dart:async';

import 'package:clock/clock.dart';
import 'package:meta/meta.dart';

import '_log.dart';
import '_utils.dart';
import 'cache/cache.dart';
import 'error.dart';
import 'file_collection.dart';
import 'task_invocation.dart';
import 'task_run.dart';

/// A run condition for a [Task].
///
/// A [Task] should not run if its [RunCondition] does not allow it.
mixin RunCondition {
  /// Check if the provided task invocation should run.
  ///
  /// Returns true if it should, false otherwise.
  FutureOr<bool> shouldRun(TaskInvocation invocation);

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
  bool shouldRun(TaskInvocation invocation) => true;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AlwaysRun;

  @override
  int get hashCode => 46;
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
      DartleCache? cache})
      : cache = cache ?? DartleCache.instance;

  @override
  FutureOr<bool> shouldRun(TaskInvocation invocation) async {
    if (await cache.hasTaskInvocationChanged(invocation)) return true;
    final inputsChanged = await cache.hasChanged(inputs);
    if (inputsChanged) {
      logger.fine('Changes detected on task inputs: $inputs');
      return true;
    }
    final outputsChanged = await cache.hasChanged(outputs);
    if (outputsChanged) {
      logger.fine('Changes detected on task outputs: $outputs');
      return true;
    }
    await for (final output in outputs.files) {
      if (!await output.exists()) {
        logger.fine('Task output does not exist: ${output.path}');
        return true;
      }
    }
    return false;
  }

  @override
  Future<void> postRun(TaskResult result) async {
    var success = result.isSuccess;
    DartleException? error;

    if (success) {
      if (await outputs.isNotEmpty && verifyOutputsExist) {
        logger.fine('Verifying task produced expected outputs');
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
      await cache.cacheTaskInvocation(result.invocation);
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
      await cache.removeTaskInvocation(result.invocation.task.name);
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

/// A [RunCondition] which reports that a task should run at most every
/// [period].
///
/// The [period] is computed at the time of checking if the task should run and
/// starts counting from the last time the task was executed successfully.
class RunAtMostEvery with RunCondition {
  final Duration period;
  final DartleCache cache;

  RunAtMostEvery(this.period, [DartleCache? cache])
      : cache = cache ?? DartleCache.instance;

  @override
  FutureOr<void> postRun(TaskResult result) async {
    if (result.isSuccess) {
      await cache.cacheTaskInvocation(result.invocation);
    } else {
      await cache.removeTaskInvocation(result.invocation.task.name);
    }
  }

  @override
  FutureOr<bool> shouldRun(TaskInvocation invocation) async {
    if (await cache.hasTaskInvocationChanged(invocation)) return true;
    final lastTime = await cache.getLatestInvocationTime(invocation);
    if (lastTime == null) {
      return true;
    }
    return clock.now().isAfter(lastTime.add(period));
  }
}

/// Base mixin for a [RunCondition] that combines other [RunCondition]s.
mixin RunConditionCombiner implements RunCondition {
  abstract final List<RunCondition> conditions;

  @override
  FutureOr<void> postRun(TaskResult result) async {
    final errors = [];
    for (var cond in conditions) {
      try {
        await cond.postRun(result);
      } catch (e) {
        errors.add(e);
      }
    }
    if (errors.isNotEmpty) {
      throw MultipleExceptions(errors);
    }
  }
}

/// A [RunCondition] that runs if any of its conditions runs.
class OrCondition with RunConditionCombiner {
  @override
  final List<RunCondition> conditions;

  OrCondition(this.conditions) {
    if (conditions.length < 2) {
      throw DartleException(
          message: 'OrCondition requires at least two conditions');
    }
  }

  @override
  FutureOr<bool> shouldRun(TaskInvocation invocation) async {
    for (var cond in conditions) {
      if (await cond.shouldRun(invocation)) return true;
    }
    return false;
  }
}

/// A [RunCondition] that runs if all of its conditions runs.
class AndCondition with RunConditionCombiner {
  @override
  final List<RunCondition> conditions;

  AndCondition(this.conditions) {
    if (conditions.length < 2) {
      throw DartleException(
          message: 'AndCondition requires at least two conditions');
    }
  }

  @override
  FutureOr<bool> shouldRun(TaskInvocation invocation) async {
    for (var cond in conditions) {
      if (!await cond.shouldRun(invocation)) return false;
    }
    return true;
  }
}
