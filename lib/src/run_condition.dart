import 'dart:async';
import 'dart:io';

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
  ///
  /// This method will not be called if the Dartle cache has been disabled.
  FutureOr<void> postRun(TaskResult result);
}

/// A [RunCondition] that uses file-system inputs and outputs.
///
/// Dartle considers these when verifying implicit dependencies between tasks.
mixin FilesCondition on RunCondition {
  /// Inputs which should be monitored for changes.
  FileCollection get inputs => FileCollection.empty;

  /// Outputs which should be monitored for changes.
  FileCollection get outputs => FileCollection.empty;

  /// Deletions which are expected to be performed after an action has run.
  FileCollection get deletions => FileCollection.empty;
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

  @override
  String toString() => 'AlwaysRun';
}

/// A [RunCondition] which reports that a task should run whenever its inputs
/// or outputs have changed since the last build.
///
/// If an empty [FileCollection] is given as both inputs and outputs,
/// because an empty collection will never change, [shouldRun] will never
/// return true, hence using this class in this way is likely a mistake.
class RunOnChanges with RunCondition, FilesCondition {
  @override
  final FileCollection inputs;
  @override
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
    final inputsChanged = await cache.hasChanged(inputs, key: invocation.name);
    if (inputsChanged) {
      logger.fine('Changes detected on task inputs: $inputs');
      return true;
    }
    final outputsChanged =
        await cache.hasChanged(outputs, key: invocation.name);
    if (outputsChanged) {
      logger.fine('Changes detected on task outputs: $outputs');
      return true;
    }
    return false;
  }

  @override
  Future<void> postRun(TaskResult result) async {
    var success = result.isSuccess;
    DartleException? error;

    if (success) {
      if (outputs.isNotEmpty && verifyOutputsExist) {
        logger.fine('Verifying task produced expected outputs');
        try {
          await _verifyOutputs();
        } on DartleException catch (e) {
          success = false;
          error = e;
        }
      }
    }

    final taskName = result.invocation.name;
    logger.fine(() => "Updating cached artifacts for task '$taskName'");
    if (success) {
      await cache.clean(key: taskName);
      await cache(inputs, key: taskName);
      await cache(outputs, key: taskName);
      await cache.cacheTaskInvocation(result.invocation);
    } else {
      if (outputs.isEmpty) {
        // the task failed without any outputs, so for it to run again next
        // time we need to remove its inputs
        await cache.remove(inputs, key: taskName);
      } else {
        // just forget the outputs of the failed task as they
        // may not be correct anymore
        await cache.remove(outputs, key: taskName);
      }
      await cache.removeTaskInvocation(taskName);
      if (error != null) throw error;
    }
  }

  Future<void> _verifyOutputs() async {
    final missingOutputs = <String>[];
    for (final entity in outputs.includedEntities()) {
      if (!await entity.exists()) missingOutputs.add(entity.path);
    }
    if (missingOutputs.isNotEmpty) {
      throw DartleException(
          message: 'task did not produce the following expected outputs:\n'
              '${missingOutputs.map((f) => '  * $f').join('\n')}');
    }
  }

  @override
  String toString() {
    return 'RunOnChanges{inputs: $inputs, outputs: $outputs}';
  }
}

/// A [RunCondition] which reports that a task should run at most every
/// [period].
///
/// The [period] is computed at the time of checking if the task should run and
/// starts counting from the last time the task was executed successfully.
@sealed
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
      await cache.removeTaskInvocation(result.invocation.name);
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

  @override
  String toString() => 'RunAtMostEvery{$period}';
}

/// A [RunCondition] that indicates that a [Task] will delete certain files
/// and directories if they exist.
///
/// Build cleaning tasks should use this condition so that Dartle will know how
/// to enforce the correct execution of tasks whose inputs/outputs may be
/// affected by deletion tasks.
@sealed
class RunToDelete with RunCondition, FilesCondition {
  @override
  final FileCollection deletions;
  final DartleCache cache;

  /// Whether to verify that all declared deletions have been performed
  /// after the task has run.
  final bool verifyDeletions;

  RunToDelete(
    this.deletions, {
    this.verifyDeletions = true,
    DartleCache? cache,
  }) : cache = cache ?? DartleCache.instance;

  @override
  FileCollection get inputs => FileCollection.empty;

  @override
  FileCollection get outputs => FileCollection.empty;

  @override
  FutureOr<bool> shouldRun(TaskInvocation invocation) async {
    return await deletions.resolve().asyncAny((f) => f.entity.exists());
  }

  @override
  FutureOr<void> postRun(TaskResult result) async {
    if (verifyDeletions) {
      final failedToDelete = await _collectNotDeleted().toList();
      if (failedToDelete.isNotEmpty) {
        final taskName = result.invocation.name;
        throw DartleException(
            message:
                "task '$taskName' did not delete the following expected entities:\n"
                '${failedToDelete.map((f) => '  * $f').join('\n')}');
      }
    }
  }

  Stream<FileSystemEntity> _collectNotDeleted() async* {
    await for (final entry in deletions.resolve()) {
      if (await entry.entity.exists()) {
        yield entry.entity;
      }
    }
  }

  @override
  String toString() {
    if (deletions.isEmpty) return 'EmptyRunToDelete';
    return 'RunToDelete{$deletions}';
  }
}

/// Base mixin for a [RunCondition] that combines other [RunCondition]s.
mixin RunConditionCombiner implements RunCondition {
  abstract final List<RunCondition> conditions;

  @override
  FutureOr<void> postRun(TaskResult result) async {
    final errors = <ExceptionAndStackTrace>[];
    for (var cond in conditions) {
      try {
        await cond.postRun(result);
      } on Exception catch (e, st) {
        errors.add(ExceptionAndStackTrace(e, st));
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

  @override
  String toString() => conditions.join(' OR ');
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

  @override
  String toString() => conditions.join(' AND ');
}
