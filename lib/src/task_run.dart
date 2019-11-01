import '_log.dart';
import '_utils.dart';
import 'error.dart';
import 'helpers.dart';
import 'task.dart';

/// Calls [runTask] with each given task, in turn.
Future<void> runTasks(List<Task> tasks) async {
  for (final task in tasks) {
    await runTask(task);
  }
}

/// Run a task unconditionally.
///
/// The task's [Task.runCondition] is is not checked before running the task,
/// but its [RunCondition.afterRun] method is called with the correct result.
///
/// Any errors running the task cause the [failBuild] function to be called
/// with the appropriate error, exiting the build.
Future<void> runTask(Task task) async {
  logger.info("Running task '${task.name}'");
  final stopwatch = Stopwatch()..start();
  try {
    await task.action();
    stopwatch.stop(); // do not include runCondition in the reported time
    await _runTaskSuccessfulAfterRun(task);
  } on Exception catch (e) {
    stopwatch.stop();
    try {
      await task.runCondition.afterRun(wasSuccessful: false);
    } finally {
      String reason = '';
      if (e is DartleException) {
        reason = e.message;
      }
      if (reason.isEmpty) reason = e.toString();
      failBuild(reason: "Task '${task.name}' failed due to: $reason");
    }
  } finally {
    logger.debug("Task '${task.name}' completed in ${elapsedTime(stopwatch)}");
  }
}

Future _runTaskSuccessfulAfterRun(Task task) async {
  try {
    await task.runCondition.afterRun(wasSuccessful: true);
  } on Exception catch (e) {
    failBuild(reason: "Task '${task.name}' failed due to: $e");
  }
}
