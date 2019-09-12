import 'package:meta/meta.dart';

import '_log.dart';
import '_options.dart';
import 'error.dart';
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
    var taskNames = parseOptionsAndGetTasks(args);
    if (taskNames.isEmpty && defaultTasks != null) {
      taskNames = defaultTasks.map((t) => t.name).toList();
    }
    final executableTasks = await _getExecutableTasks(tasks, taskNames);
    logger.info("Executing ${executableTasks.length} task(s) out of "
        "${taskNames.length} selected task(s)");
    await _runTasks(executableTasks);
  } on DartleException catch (e) {
    failBuild(reason: e.message, exitCode: e.exitCode);
  } on Exception catch (e) {
    failBuild(reason: 'Unexpected error: $e');
  } finally {
    stopWatch.stop();
    logger.info("Build succeeded in ${_elapsedTime(stopWatch)}");
  }
}

Future<List<Task>> _getExecutableTasks(
    List<Task> tasks, List<String> taskNames) async {
  if (taskNames.isEmpty) {
    return failBuild(
        reason: 'No tasks were explicitly selected and '
            'no default tasks were provided') as List<Task>;
  } else {
    final taskMap = tasks.asMap().map((_, task) => MapEntry(task.name, task));
    final result = <Task>[];
    for (final taskName in taskNames) {
      final task = taskMap[taskName];
      if (task == null) {
        return failBuild(reason: "Unknown task or option: ${taskName}")
            as List<Task>;
      }
      if (await task.runCondition?.shouldRun() ?? true) {
        result.add(task);
      } else {
        logger.debug("Skipping task: ${task.name} as it is up-to-date");
      }
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
  logger.info("Running task: ${task.name}");
  final stopwatch = Stopwatch()..start();
  try {
    await task.action();
    stopwatch.stop(); // do not include runCondition in the reported time
    await _runTaskSuccessfulAfterRun(task);
  } on Exception catch (e) {
    stopwatch.stop();
    try {
      await task.runCondition?.afterRun(false);
    } finally {
      String reason;
      if (e is DartleException) {
        reason = e.message;
      } else {
        reason = e.toString();
      }
      failBuild(reason: "Task ${task.name} failed due to: $reason");
    }
  } finally {
    logger.debug("Task ${task.name} completed in ${_elapsedTime(stopwatch)}");
  }
}

Future _runTaskSuccessfulAfterRun(Task task) async {
  try {
    await task.runCondition?.afterRun(true);
  } on Exception catch (e) {
    failBuild(reason: "Task ${task.name} failed due to: $e");
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
