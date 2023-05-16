import 'dart:async';

import 'package:collection/collection.dart';
import 'package:logging/logging.dart';
import 'package:structured_async/structured_async.dart';

import '_actor_task.dart';
import '_log.dart';
import '_utils.dart';
import 'cache/cache.dart';
import 'error.dart';
import 'run_condition.dart';
import 'task.dart';
import 'task_invocation.dart';

/// Result of executing a [Task].
class TaskResult {
  final TaskInvocation invocation;
  final ExceptionAndStackTrace? exceptionAndStackTrace;

  Exception? get error => exceptionAndStackTrace?.exception;

  TaskResult(this.invocation, [this.exceptionAndStackTrace]);

  /// Whether this task result is successful.
  bool get isSuccess => error == null;

  /// Whether this task result is a failure.
  bool get isFailure => !isSuccess;

  /// Whether this task result is due to a task having been cancelled.
  /// If this is `true`, [isFailure] will also be `true`.
  bool get isCancelled => error is FutureCancelled;

  @override
  String toString() {
    return 'TaskResult{invocation: $invocation, error: $error}';
  }
}

/// Signature of the action of incremental [Task]s.
///
/// When there are no changes, the [Task] will not run.
/// The changes Lists reflects what has changed since the
/// last time the [Task] executed successfully.
///
/// Only [Task]s that have a `runCondition` of type [RunOnChanges] can receive
/// input/output changes.
///
/// Notice that the full set of changes are only collected if a
/// [Task] action requires them.
typedef IncrementalAction = FutureOr<void> Function(List<String> args,
    [ChangeSet? changeSet]);

/// The change Set for an incremental action.
class ChangeSet {
  final List<FileChange> inputChanges;
  final List<FileChange> outputChanges;

  const ChangeSet(this.inputChanges, this.outputChanges);
}

/// Calls [runTask] with each given task that must run.
///
/// At the end of each [TaskPhase], the executed
/// tasks' [RunCondition.postRun] actions are also run, unless `disableCache`
/// is set to `true`.
///
/// Returns the result of each executed task. If a task fails, execution
/// stops and only the results thus far accumulated are returned.
///
/// If a task's [RunCondition.postRun] action fails, a [MultipleExceptions]
/// is thrown with all accumulated errors up to the end of the phase the task
/// belongs to, including from other task's actions and `postRun`s.
/// Notice that [MultipleExceptions] is not thrown in case there are
/// task failures, but no post-run action failures.
///
/// Tasks within each [ParallelTasks] entry are always called "simultaneously",
/// then their [Future] results are awaited in order. If [parallelize] is true,
/// then all tasks that return true for [Task.isParallelizable] will be run
/// within [Isolate]s, achieving true parallelism.
///
/// This method does not throw any Exception, failures are returned
/// as [TaskResult] instances with errors.
Future<List<TaskResult>> runTasks(List<ParallelTasks> tasks,
    {required bool parallelize, bool disableCache = false}) async {
  if (logger.isLoggable(Level.FINE)) {
    final execMode = parallelize
        ? 'in parallel where possible, using separate Isolates for parallelizable Tasks'
        : 'on main Isolate as no parallelization was enabled';
    logger.fine('Will execute tasks $execMode');
  }

  return await _run(tasks,
      parallelize: parallelize, disableCache: disableCache);
}

Future<List<TaskResult>> _run(List<ParallelTasks> tasks,
    {required bool parallelize, required bool disableCache}) async {
  final results = <TaskResult>[];
  final phaseResults = <TaskResult>[];
  final phaseErrors = <ExceptionAndStackTrace>[];
  TaskPhase? currentPhase;

  for (final parTasks in tasks) {
    if (parTasks.tasks.isEmpty) continue;
    final isNewPhase = parTasks.phase != currentPhase;
    if (isNewPhase) {
      phaseErrors.addAll(
          await _onNewPhaseStarted(phaseResults, currentPhase, disableCache));
      phaseResults.clear();
      currentPhase = parTasks.phase;
      if (phaseErrors.isNotEmpty) {
        logger.fine('Aborting task execution due to task post-run error');
        break;
      }
    }
    final useIsolate = parallelize && parTasks.mustRunCount > 1;

    logger.fine(() =>
        "Scheduling tasks ${parTasks.tasks.map((t) => t.task.name)}"
        " to run ${useIsolate ? 'in parallel using isolates' : 'concurrently'}");

    final futureResults = CancellableFuture.stream(parTasks.tasks
        .where(_taskMustRun)
        .map((pTask) => () => runTask(pTask.invocation,
            runInIsolate: useIsolate, allowIncremental: !disableCache)));

    await for (final result in futureResults) {
      results.add(result);
      phaseResults.add(result);
    }

    if (results.any((r) => r.isFailure)) {
      logger.fine('Aborting task execution');
      break;
    }
  }

  phaseErrors.addAll(
      await _onNewPhaseStarted(phaseResults, currentPhase, disableCache));

  if (results.any((r) => r.isFailure) || phaseErrors.isNotEmpty) {
    final all = results
        .map(_toDisplayError)
        .followedBy(phaseErrors)
        .whereNotNull()
        .toList(growable: false);
    throw MultipleExceptions(all);
  }

  return results;
}

/// Run a task unconditionally.
///
/// The task's [Task.runCondition] is not checked or used by this method.
Future<TaskResult> runTask(TaskInvocation invocation,
    {required bool runInIsolate, bool allowIncremental = true}) async {
  final task = invocation.task;
  final runCondition = task.runCondition;

  final stopwatch = Stopwatch()..start();

  ChangeSet? changeSet;

  if (allowIncremental &&
      runCondition is RunOnChanges &&
      task.action is IncrementalAction) {
    changeSet =
        await _prepareIncrementalAction(stopwatch, task.name, runCondition);
  }

  final action =
      _createTaskAction(task, runInIsolate && task.isParallelizable, changeSet);

  logger.log(task.name.startsWith('_') ? Level.FINE : Level.INFO,
      "Running task '${task.name}'");

  stopwatch.reset();

  TaskResult result;
  try {
    final args = invocation.args;
    await action(args, changeSet);
    stopwatch.stop();
    result = TaskResult(invocation);
  } catch (e, st) {
    stopwatch.stop();
    result = TaskResult(invocation,
        ExceptionAndStackTrace(e is Exception ? e : Exception(e), st));

    // other tasks should be cancelled if there's a failure
    currentCancellableContext()?.cancel();
  }
  if (logger.isLoggable(profile)) {
    final completionReason = result.isSuccess
        ? 'successfully'
        : result.isCancelled
            ? 'due to being cancelled'
            : 'with errors';
    logger.log(
        profile,
        "Task '${task.name}' completed "
        '$completionReason in ${elapsedTime(stopwatch)}');
  }
  return result;
}

Future<ChangeSet> _prepareIncrementalAction(
    Stopwatch stopwatch, String taskName, RunOnChanges runCondition) async {
  logger.fine(() => "Collecting changes for incremental task '$taskName'");

  final inputChanges = await runCondition.cache
      .findChanges(runCondition.inputs, key: taskName)
      .toList();

  final outputChanges = await runCondition.cache
      .findChanges(runCondition.outputs, key: taskName)
      .toList();

  logger.log(
      profile,
      () =>
          "Collected ${inputChanges.length} input and ${outputChanges.length} output "
          "change(s) for '$taskName' in ${elapsedTime(stopwatch)}");

  return ChangeSet(inputChanges, outputChanges);
}

bool _taskMustRun(TaskWithStatus pTask) {
  final willRun = pTask.mustRun;
  logger.fine(() => "Task '${pTask.task.name}' will "
      "${willRun ? 'run' : 'be skipped'} because it has status "
      '${pTask.status}');
  return willRun;
}

MaybeIncrementalAction _createTaskAction(
    Task task, bool runInIsolate, ChangeSet? changes) {
  return runInIsolate
      ? actorAction(task.action)
      : (args, changes) async => await runAction(task.action, args, changes);
}

Future<List<ExceptionAndStackTrace>> _onNewPhaseStarted(
    List<TaskResult> phaseResults,
    TaskPhase? phaseEnded,
    bool disableCache) async {
  if (phaseResults.isEmpty) return const [];
  logger.fine(() {
    final phaseMsg =
        phaseEnded == null ? '' : " after phase '${phaseEnded.name}' ended";
    return 'Running post-run actions$phaseMsg.';
  });
  if (disableCache) {
    return const [];
  }
  return await runTasksPostRun(phaseResults);
}

ExceptionAndStackTrace? _toDisplayError(TaskResult result) {
  final exSt = result.exceptionAndStackTrace;
  if (exSt == null) return null;
  final prefix = "Task '${result.invocation.name}'";
  final error = exSt.exception;
  DartleException dartleException;
  if (error is FutureCancelled) {
    dartleException =
        DartleException(message: '$prefix was cancelled', exitCode: 4);
  } else if (error is DartleException) {
    dartleException = error.withMessage('$prefix failed: ${error.message}');
  } else {
    dartleException =
        DartleException(message: '$prefix failed: $error', exitCode: 2);
  }
  return exSt.withException(dartleException);
}

Future<List<ExceptionAndStackTrace>> runTasksPostRun(
    List<TaskResult> results) async {
  final errors = <ExceptionAndStackTrace>[];
  for (final result in results) {
    try {
      await runTaskPostRun(result);
    } on Exception catch (e, st) {
      errors.add(ExceptionAndStackTrace(e, st));
    }
  }
  return errors;
}

Future<void> runTaskPostRun(TaskResult taskResult) async {
  final task = taskResult.invocation.task;
  var isError = false;
  logger.fine("Running post-run action for task '${task.name}'");
  final stopwatch = Stopwatch()..start();
  try {
    await task.runCondition.postRun(taskResult);
    stopwatch.stop();
  } on Exception {
    stopwatch.stop();
    isError = true;
    rethrow;
  } finally {
    logger.log(
        profile,
        "Post-run action of task '${task.name}' completed "
        "${!isError ? 'successfully' : 'with errors'}"
        ' in ${elapsedTime(stopwatch)}');
  }
}
