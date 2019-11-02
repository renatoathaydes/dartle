import 'package:meta/meta.dart';

import '_log.dart';
import '_utils.dart';
import 'cache.dart';
import 'error.dart';
import 'helpers.dart';
import 'options.dart';
import 'task.dart';
import 'task_run.dart';

/// Initializes the dartle library and runs the tasks selected by the user
/// (or in the provided [args]).
///
/// This method may not return if some error is found, as dartle will
/// call [exit(code)] with the appropriate error code.
Future<void> run(List<String> args,
    {@required List<Task> tasks, List<Task> defaultTasks = const []}) async {
  final stopWatch = Stopwatch()..start();

  final options = parseOptions(args);
  if (options.showHelp) {
    return print(dartleUsage);
  }

  activateLogging(options.logLevel);

  if (options.resetCache) {
    await DartleCache.instance.clean();
  }

  try {
    var taskNames = options.requestedTasks;
    if (taskNames.isEmpty && defaultTasks.isNotEmpty) {
      taskNames = defaultTasks.map((t) => t.name).toList();
    }
    final executableTasks =
        await _getExecutableTasks(tasks, taskNames, options.forceTasks);
    logger.info("Executing ${executableTasks.length} task(s) out of "
        "${taskNames.length} selected task(s)");
    await _runAll(executableTasks);
  } on DartleException catch (e) {
    logger.warn("Build failed in ${elapsedTime(stopWatch)}");
    failBuild(reason: e.message, exitCode: e.exitCode);
  } on Exception catch (e) {
    failBuild(reason: 'Unexpected error: $e');
  } finally {
    stopWatch.stop();
    logger.info("Build succeeded in ${elapsedTime(stopWatch)}");
  }
}

Future<void> _runAll(List<Task> executableTasks) async {
  final results = await runTasks(executableTasks);
  final failures = results.where((r) => r.isFailure).toList(growable: false);
  final postRunFailures = await runTasksPostRun(results);

  final allErrors = <Exception>[];

  allErrors.addAll(failures.map((f) => f.error));
  allErrors.addAll(postRunFailures);

  if (allErrors.isNotEmpty) {
    _throwAggregateErrors(allErrors);
  }
}

Future<List<Task>> _getExecutableTasks(
    List<Task> tasks, List<String> requestedTasks, bool forceTasks) async {
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
        return failBuild(reason: "Unknown task or option: '${taskNameSpec}'")
            as List<Task>;
      }
      if (forceTasks) {
        logger.debug("Will force execution of task '${task.name}'");
        result.add(task);
      } else if (await task.runCondition.shouldRun()) {
        result.add(task);
      } else {
        logger.debug("Skipping task '${task.name}' as it is up-to-date");
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

void _throwAggregateErrors(List<Exception> errors) {
  if (errors.isEmpty) return;
  if (errors.length == 1) throw errors[0];

  int exitCode = 1;
  for (final dartleException in errors.whereType<DartleException>()) {
    exitCode = dartleException.exitCode;
    break;
  }
  final messageBuilder = StringBuffer('Several errors have occurred:\n');
  for (final error in errors) {
    String errorMessage;
    if (error is DartleException) {
      errorMessage = error.message;
    } else {
      errorMessage = error.toString();
    }
    messageBuilder
      ..write('  * ')
      ..writeln(errorMessage);
  }
  throw DartleException(message: messageBuilder.toString(), exitCode: exitCode);
}
