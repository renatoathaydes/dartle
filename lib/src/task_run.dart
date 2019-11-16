import 'dart:async';

import 'package:meta/meta.dart';

import '_actor_task.dart';
import '_log.dart';
import '_utils.dart';
import 'task.dart';
import 'task_invocation.dart';

/// Result of executing a [Task].
class TaskResult {
  final Task task;
  final Exception error;

  TaskResult(this.task, [this.error]);

  bool get isSuccess => error == null;

  bool get isFailure => !isSuccess;
}

/// Calls [runTask] with each given task.
///
/// Returns the result of each executed task. If a task fails, execution
/// stops and only the results thus far accumulated are returned.
///
/// Tasks within each [ParallelTasks] entry are always called "simultaneously",
/// then their [Future] results are awaited in order. If [parallelize] is true,
/// then all tasks that return true for [Task.isParallelizable] will be run
/// within [Isolate]s, achieving true parallelism.
///
/// This method does not throw any Exception, failures are returned
/// as [TaskResult] instances with errors.
Future<List<TaskResult>> runTasks(List<ParallelTasks> tasks,
    {@required bool parallelize}) async {
  if (logger.isLevelEnabled(LogLevel.debug)) {
    final execMode = parallelize
        ? 'in parallel where possible, using separate Isolates for parallelizable Tasks'
        : 'on main Isolate as no parallelization was enabled';
    logger.debug("Will execute tasks ${execMode}");
  }
  final results = <TaskResult>[];
  for (final parTasks in tasks) {
    final useIsolate = parallelize && parTasks.invocations.length > 1;
    final futureResults = parTasks.invocations
        .map((invocation) => runTask(invocation, runInIsolate: useIsolate))
        .toList(growable: false);
    for (final futureResult in futureResults) {
      results.add(await futureResult);
    }

    if (results.any((r) => r.isFailure)) {
      logger.debug("Aborting task execution due to failure");
      return results;
    }
  }
  return results;
}

/// Run a task unconditionally.
///
/// The task's [Task.runCondition] is not checked or used by this method.
Future<TaskResult> runTask(TaskInvocation invocation,
    {@required bool runInIsolate}) async {
  final task = invocation.task;
  logger.info("Running task '${task.name}'");

  bool useIsolate = runInIsolate && task.isParallelizable;

  logger.debug("Using ${useIsolate ? 'separate' : 'main'} "
      "Isolate to run task '${task.name}'");

  final action = useIsolate ? actorAction(task.action) : task.action;
  final stopwatch = Stopwatch()..start();
  TaskResult result;
  try {
    await action(invocation.args);
    stopwatch.stop();
    result = TaskResult(task);
  } on Exception catch (e) {
    stopwatch.stop();
    result = TaskResult(task, e);
  }
  logger.debug("Task '${task.name}' completed "
      "${result.isSuccess ? 'successfully' : 'with errors'}"
      " in ${elapsedTime(stopwatch)}");
  return result;
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
  final task = taskResult.task;
  bool isError = false;
  logger.debug("Running post-run action for task '${task.name}'");
  final stopwatch = Stopwatch()..start();
  try {
    await task.runCondition.postRun(taskResult);
    stopwatch.stop();
  } on Exception {
    stopwatch.stop();
    isError = true;
    rethrow;
  } finally {
    logger.debug("Post-run action of task '${task.name}' completed "
        "${!isError ? 'successfully' : 'with errors'}"
        " in ${elapsedTime(stopwatch)}");
  }
}
