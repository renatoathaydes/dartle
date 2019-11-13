import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:logging/logging.dart' as log;
import 'package:meta/meta.dart';

import '_log.dart';
import '_task_graph.dart';
import '_utils.dart';
import 'cache.dart';
import 'dartle_version.g.dart';
import 'error.dart';
import 'helpers.dart';
import 'options.dart';
import 'run_condition.dart';
import 'task.dart';
import 'task_run.dart';

/// Initializes the dartle library and runs the tasks selected by the user
/// (or in the provided [args]).
///
/// This method will normally not return as Dartle will exit with the
/// appropriate code. To avoid that, set [doNotExit] to [true].
Future<void> run(List<String> args,
    {@required Set<Task> tasks,
    Set<Task> defaultTasks = const {},
    bool doNotExit = false}) async {
  final stopWatch = Stopwatch()..start();
  Options options = const Options();

  try {
    options = parseOptions(args);
    await _runWithoutErrorHandling(args, tasks, defaultTasks, options);
    stopWatch.stop();
    if (!options.showInfoOnly && options.logBuildTime) {
      logger.info("Build succeeded in ${elapsedTime(stopWatch)}");
    }
    if (!doNotExit) exit(0);
  } on DartleException catch (e) {
    activateLogging(log.Level.WARNING);
    logger.error(e.message);
    if (options.logBuildTime) {
      logger.error("Build failed in ${elapsedTime(stopWatch)}");
    }
    if (!doNotExit) exit(e.exitCode);
  } on Exception catch (e) {
    activateLogging(log.Level.WARNING);
    logger.error("Unexpected error: $e");
    if (options.logBuildTime) {
      logger.error("Build failed in ${elapsedTime(stopWatch)}");
    }
    if (!doNotExit) exit(22);
  }
}

Future<void> _runWithoutErrorHandling(List<String> args, Set<Task> tasks,
    Set<Task> defaultTasks, Options options) async {
  if (options.showHelp) {
    return print(dartleUsage);
  }
  if (options.showVersion) {
    return print("Dartle version ${dartleVersion}");
  }

  activateLogging(options.logLevel);
  logger.debug("Dartle version: ${dartleVersion}");

  if (options.resetCache) {
    await DartleCache.instance.clean();
  }

  var taskNames = options.requestedTasks;
  if (taskNames.isEmpty && defaultTasks.isNotEmpty) {
    taskNames = defaultTasks.map((t) => t.name).toList();
  }
  final taskMap = createTaskMap(tasks);
  final executableTasks =
      await _getExecutableTasks(taskMap, taskNames, options);
  if (options.showInfoOnly) {
    print("======== Showing build information only, no tasks will "
        "be executed ========\n");
    showTasksInfo(executableTasks, taskMap, defaultTasks, options);
  } else {
    if (logger.isLevelEnabled(LogLevel.info)) {
      String taskPhrase(int count) =>
          count == 1 ? "$count task" : "$count tasks";
      final totalTasksPhrase = taskPhrase(tasks.length);
      final requestedTasksPhrase = taskPhrase(taskNames.length);
      final executableTasksCount =
          executableTasks.expand((t) => t.tasks).length;
      final executableTasksPhrase = taskPhrase(executableTasksCount);
      final dependentTasksCount =
          max(0, executableTasksCount - taskNames.length);

      logger.info("Executing $executableTasksPhrase out of a total of "
          "$totalTasksPhrase: $requestedTasksPhrase selected, "
          "$dependentTasksCount due to dependencies");
    }

    await _runAll(executableTasks, options);
  }
}

Future<void> _runAll(
    List<ParallelTasks> executableTasks, Options options) async {
  final allErrors = <Exception>[];

  final results =
      await runTasks(executableTasks, parallelize: options.parallelizeTasks);
  final failures = results.where((r) => r.isFailure).toList(growable: false);
  final postRunFailures = await runTasksPostRun(results);

  allErrors.addAll(failures.map((f) => f.error));
  allErrors.addAll(postRunFailures);

  if (allErrors.isNotEmpty) {
    _throwAggregateErrors(allErrors);
  }
}

Future<List<ParallelTasks>> _getExecutableTasks(
    Map<String, TaskWithDeps> taskMap,
    List<String> requestedTasks,
    Options options) async {
  if (requestedTasks.isEmpty) {
    if (!options.showInfoOnly) {
      logger.warn("No tasks were requested and no default tasks exist.");
    }
    return const [];
  }

  final mustRun = <TaskWithDeps>[];
  for (final taskNameSpec in requestedTasks) {
    final task = _findTaskByName(taskMap, taskNameSpec);
    if (task == null) {
      if (options.showInfoOnly) {
        logger.warn("Task '$taskNameSpec' does not exist.");
        continue;
      }
      return failBuild(reason: "Unknown task: '${taskNameSpec}'")
          as List<ParallelTasks>;
    }
    if (options.forceTasks) {
      logger.debug("Will force execution of task '${task.name}'");
      mustRun.add(task);
    } else if (await task.runCondition.shouldRun()) {
      mustRun.add(task);
    } else {
      if (options.showTasks) {
        logger.info("Task '${task.name}' is up-to-date");
      } else {
        logger.debug("Skipping task '${task.name}' as it is up-to-date");
      }
    }
  }
  return await getInOrderOfExecution(mustRun);
}

/// Get the tasks in the order that they should be executed, taking into account
/// their dependencies.
///
/// All the tasks provided directly in the [tasks] list will be returned, as
/// their [RunCondition] are not checked. However, their dependencies'
/// [RunCondition] will be checked, and only those that should run will be
/// included in the returned list.
Future<List<ParallelTasks>> getInOrderOfExecution(
    List<TaskWithDeps> tasks) async {
  // first of all, re-order tasks so that dependencies are in order
  tasks.sort();

  final result = <ParallelTasks>[];
  final seenTasks = <String>{};

  Future<void> addTaskOnce(TaskWithDeps task, bool checkShouldRun) async {
    if (seenTasks.add(task.name)) {
      if (!checkShouldRun || await task.runCondition.shouldRun()) {
        final canRunInPreviousGroup =
            result.isNotEmpty && result.last.canInclude(task);
        if (canRunInPreviousGroup) {
          result.last.tasks.add(task);
        } else {
          result.add(ParallelTasks()..tasks.add(task));
        }
      }
    }
  }

  // de-duplicate tasks, adding their dependencies first
  for (final taskWithDeps in tasks) {
    for (final dep in taskWithDeps.dependencies) {
      await addTaskOnce(dep, true);
    }
    await addTaskOnce(taskWithDeps, false);
  }
  return result;
}

TaskWithDeps _findTaskByName(
    Map<String, TaskWithDeps> taskMap, String nameSpec) {
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
