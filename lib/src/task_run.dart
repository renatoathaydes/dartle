import '_log.dart';
import '_utils.dart';
import 'task.dart';

/// Result of executing a [Task].
class TaskResult {
  final Task task;
  final Exception error;

  TaskResult(this.task, [this.error]);

  bool get isSuccess => error == null;

  bool get isFailure => !isSuccess;
}

/// Calls [runTask] with each given task, in turn.
///
/// Returns the result of each executed task. If a task fails, execution
/// stops and only the results thus far accumulated are returned.
///
/// This method does not throw any Exception, failures are returned
/// as [TaskResult] instances with errors.
Future<List<TaskResult>> runTasks(List<ParallelTasks> tasks) async {
  final results = <TaskResult>[];
  for (final parTasks in tasks) {
    // TODO run in parallel
    for (final task in parTasks.tasks) {
      var result = await runTask(task);
      results.add(result);
      if (result.isFailure) {
        logger.debug("Aborting task execution due to failure");
        return results;
      }
    }
  }
  return results;
}

/// Run a task unconditionally.
///
/// The task's [Task.runCondition] is not checked or used by this method.
Future<TaskResult> runTask(Task task) async {
  logger.info("Running task '${task.name}'");
  final stopwatch = Stopwatch()..start();
  TaskResult result;
  try {
    await task.action();
    stopwatch.stop();
    result = TaskResult(task);
  } on Exception catch (e) {
    stopwatch.stop();
    result = TaskResult(task, e);
  } finally {
    logger.debug("Task '${task.name}' completed "
        "${result.isSuccess ? 'successfully' : 'with errors'}"
        " in ${elapsedTime(stopwatch)}");
  }
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
