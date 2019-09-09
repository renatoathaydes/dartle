import 'package:dartle/dartle.dart';
import 'package:meta/meta.dart';

import '_log.dart';
import '_options.dart';
import 'helpers.dart';
import 'task.dart';

/// Initializes the dartle library's configuration without executing any
/// tasks.
void configure(List<String> args) {
  activateLogging();
  parseOptionsAndGetTasks(args);
}

/// Initializes the dartle library and runs the tasks selected by the user
/// (or in the provided [args]).
///
/// This method may not return if some error is found, as dartle will
/// call [exit(code)] with the appropriate error code.
Future<void> run(List<String> args,
    {@required List<Task> tasks, List<Task> defaultTasks}) async {
  final stopWatch = Stopwatch()..start();
  configure(args);
  logger.debug("Configured dartle in ${_elapsedTime(stopWatch)}");
  try {
    final taskNames = parseOptionsAndGetTasks(args);
    final executableTasks = _getExecutableTasks(tasks, defaultTasks, taskNames);
    await _runTasks(executableTasks);
  } finally {
    stopWatch.stop();
    logger.info("Build succeeded in ${_elapsedTime(stopWatch)}");
  }
}

List<Task> _getExecutableTasks(
    List<Task> tasks, List<Task> defaultTasks, List<String> taskNames) {
  if (taskNames.isEmpty) {
    return defaultTasks ?? tasks;
  } else {
    final taskMap = tasks.asMap().map((_, task) => MapEntry(task.name, task));
    final result = <Task>[];
    for (final taskName in taskNames) {
      final task = taskMap[taskName];
      if (task == null) {
        return failBuild(reason: "Unknown task or option: ${taskName}")
            as List<Task>;
      }
      result.add(task);
    }
    return result;
  }
}

Future<void> _runTasks(List<Task> tasks) async {
  for (final task in tasks) {
    await _runTask(task);
  }
}

Future<void> _runTask(Task task) async {
  if (await task.runCondition?.shouldRun() ?? true) {
    logger.info("Running task: ${task.name}");
    final stopwatch = Stopwatch()..start();
    try {
      await task.action();
      stopwatch.stop(); // do not include runCondition in the reported time
      await task.runCondition?.afterRun(true);
    } on Exception catch (e) {
      stopwatch.stop();
      try {
        await task.runCondition?.afterRun(false);
      } finally {
        failBuild(reason: "Task ${task.name} failed due to $e");
      }
    } finally {
      logger.debug("Task ${task.name} completed in ${_elapsedTime(stopwatch)}");
    }
  } else {
    logger.debug("Skipping task: ${task.name} as it is up-to-date");
  }
}

String _elapsedTime(Stopwatch stopwatch) {
  final millis = stopwatch.elapsedMilliseconds;
  if (millis > 1000) {
    final secs = (millis * 1e-3).toStringAsPrecision(4);
    return "${secs} seconds";
  } else {
    return "${millis} ms";
  }
}
