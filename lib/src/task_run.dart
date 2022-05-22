import 'dart:async';

import 'package:logging/logging.dart';

import '_actor_task.dart';
import '_log.dart';
import '_utils.dart';
import 'error.dart';
import 'task.dart';
import 'task_invocation.dart';

/// Result of executing a [Task].
class TaskResult {
  final TaskInvocation invocation;
  final Exception? error;

  TaskResult(this.invocation, [this.error]);

  bool get isSuccess => error == null;

  bool get isFailure => !isSuccess;
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

  final results = <TaskResult>[];
  final phaseResults = <TaskResult>[];
  final phaseErrors = <Exception>[];
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
    final futureResults = parTasks.tasks
        .where(_taskMustRun)
        .map((pTask) => runTask(pTask.invocation, runInIsolate: useIsolate))
        .toList(growable: false);

    for (final futureResult in futureResults) {
      final result = await futureResult;
      results.add(result);
      phaseResults.add(result);
    }

    if (results.any((r) => r.isFailure)) {
      logger.fine('Aborting task execution due to task failure');
      break;
    }
  }

  phaseErrors.addAll(await _onNewPhaseStarted(phaseResults, currentPhase));

  if (phaseErrors.isNotEmpty) {
    // include the task errors as well
    final taskErrors = results
        .map((f) => f.error)
        .whereType<Exception>()
        .toList(growable: false);
    throw MultipleExceptions(taskErrors.followedBy(phaseErrors).toList());
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
  } on Exception catch (e) {
    stopwatch.stop();
    result = TaskResult(invocation, e);
  }
  logger.fine("Task '${task.name}' completed "
      "${result.isSuccess ? 'successfully' : 'with errors'}"
      ' in ${elapsedTime(stopwatch)}');
  return result;
}

bool _taskMustRun(TaskWithStatus pTask) {
  final willRun = pTask.mustRun;
  logger.fine(() => "Task '${pTask.task.name}' will "
      "${willRun ? 'run' : 'be skipped'} because it has status "
      '${pTask.status}');
  return willRun;
}

Function(List<String>) _createTaskAction(Task task, bool runInIsolate) {
  logger.fine("Scheduling task '${task.name}'" +
      (runInIsolate ? ' to run in parallel' : ''));

  return runInIsolate ? actorAction(task.action) : task.action;
}

Future<List<Exception>> _onNewPhaseStarted(
    List<TaskResult> results, TaskPhase? phaseEnded) async {
  if (results.isEmpty) return const [];
  logger.fine(() {
    final phaseMsg =
        phaseEnded == null ? '' : " after phase '${phaseEnded.name}' ended";
    return 'Running post-run actions$phaseMsg.';
  });
  try {
    return await runTasksPostRun(results);
  } finally {
    results.clear();
  }
}

Future<List<Exception>> runTasksPostRun(List<TaskResult> results) async {
  final errors = <Exception>[];
  for (final result in results) {
    try {
      await runTaskPostRun(result);
    } on Exception catch (e) {
      errors.add(e);
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
    logger.fine("Post-run action of task '${task.name}' completed "
        "${!isError ? 'successfully' : 'with errors'}"
        ' in ${elapsedTime(stopwatch)}');
  }
}
