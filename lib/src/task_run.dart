import 'dart:async';

import 'package:collection/collection.dart';
import 'package:logging/logging.dart';
import 'package:structured_async/structured_async.dart';

import '_actor_task.dart';
import '_log.dart';
import '_utils.dart';
import 'error.dart';
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

/// Calls [runTask] with each given task that must run.
///
/// At the end of each [TaskPhase], the executed
/// tasks' [RunCondition.postRun] actions are also run.
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
    {required bool parallelize}) async {
  if (logger.isLoggable(Level.FINE)) {
    final execMode = parallelize
        ? 'in parallel where possible, using separate Isolates for parallelizable Tasks'
        : 'on main Isolate as no parallelization was enabled';
    logger.fine('Will execute tasks $execMode');
  }

  return await _run(tasks, parallelize);
}

Future<List<TaskResult>> _run(
    List<ParallelTasks> tasks, bool parallelize) async {
  final results = <TaskResult>[];
  final phaseResults = <TaskResult>[];
  final phaseErrors = <ExceptionAndStackTrace>[];
  TaskPhase? currentPhase;

  for (final parTasks in tasks) {
    if (parTasks.tasks.isEmpty) continue;
    final isNewPhase = parTasks.phase != currentPhase;
    if (isNewPhase) {
      phaseErrors.addAll(await _onNewPhaseStarted(phaseResults, currentPhase));
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
        .map((pTask) =>
            () => runTask(pTask.invocation, runInIsolate: useIsolate)));

    await for (final result in futureResults) {
      results.add(result);
      phaseResults.add(result);
    }

    if (results.any((r) => r.isFailure)) {
      logger.fine('Aborting task execution');
      break;
    }
  }

  phaseErrors.addAll(await _onNewPhaseStarted(phaseResults, currentPhase));

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
    {required bool runInIsolate}) async {
  final task = invocation.task;
  final action = _createTaskAction(task, runInIsolate && task.isParallelizable);

  logger.log(task.name.startsWith('_') ? Level.FINE : Level.INFO,
      "Running task '${task.name}'");

  final stopwatch = Stopwatch()..start();
  TaskResult result;
  try {
    final args = invocation.args;
    await action(args);
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

bool _taskMustRun(TaskWithStatus pTask) {
  final willRun = pTask.mustRun;
  logger.fine(() => "Task '${pTask.task.name}' will "
      "${willRun ? 'run' : 'be skipped'} because it has status "
      '${pTask.status}');
  return willRun;
}

Future Function(List<String>) _createTaskAction(Task task, bool runInIsolate) {
  return runInIsolate
      ? actorAction(task.action)
      : (args) async => await task.action(args);
}

Future<List<ExceptionAndStackTrace>> _onNewPhaseStarted(
    List<TaskResult> phaseResults, TaskPhase? phaseEnded) async {
  if (phaseResults.isEmpty) return const [];
  logger.fine(() {
    final phaseMsg =
        phaseEnded == null ? '' : " after phase '${phaseEnded.name}' ended";
    return 'Running post-run actions$phaseMsg.';
  });
  try {
    return await runTasksPostRun(phaseResults);
  } finally {
    phaseResults.clear();
  }
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
