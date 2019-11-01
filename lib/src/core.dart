import 'package:meta/meta.dart';

import '_log.dart';
import '_options.dart';
import 'task_run.dart';
import '_utils.dart';
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
    {@required List<Task> tasks, List<Task> defaultTasks = const []}) async {
  final stopWatch = Stopwatch()..start();
  configure(args);
  logger.debug("Configured dartle in ${elapsedTime(stopWatch)}");
  try {
    var taskNames = parseOptionsAndGetTasks(args);
    if (taskNames.isEmpty && defaultTasks.isNotEmpty) {
      taskNames = defaultTasks.map((t) => t.name).toList();
    }
    final executableTasks = await _getExecutableTasks(tasks, taskNames);
    logger.info("Executing ${executableTasks.length} task(s) out of "
        "${taskNames.length} selected task(s)");
    await runTasks(executableTasks);
  } on DartleException catch (e) {
    failBuild(reason: e.message, exitCode: e.exitCode);
  } on Exception catch (e) {
    failBuild(reason: 'Unexpected error: $e');
  } finally {
    stopWatch.stop();
    logger.info("Build succeeded in ${elapsedTime(stopWatch)}");
  }
}

Future<List<Task>> _getExecutableTasks(
    List<Task> tasks, List<String> requestedTasks) async {
  if (requestedTasks.isEmpty) {
    return failBuild(
        reason: 'No tasks were explicitly selected and '
            'no default tasks were provided') as List<Task>;
  } else {
    final taskMap = tasks.asMap().map((_, task) => MapEntry(task.name, task));
    final result = <Task>[];
    for (final taskNameSpec in requestedTasks) {
      final task = _findTaskByName(taskMap, taskNameSpec);
      if (task == null) {
        return failBuild(reason: "Unknown task or option: ${taskNameSpec}")
            as List<Task>;
      }
      if (await task.runCondition.shouldRun()) {
        result.add(task);
      } else if (forceTasksOption) {
        logger.debug("Will force execution of task: ${task.name} even though "
            "it is up-to-date");
        result.add(task);
      } else {
        logger.debug("Skipping task: ${task.name} as it is up-to-date");
      }
    }
    return result;
  }
}

Task _findTaskByName(Map<String, Task> taskMap, String nameSpec) {
  final name =
      findMatchingByWords(nameSpec, taskMap.keys.toList(growable: false));
  if (name == null) return null;
  return taskMap[name];
}
