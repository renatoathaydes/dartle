import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart';

import '_log.dart';
import '_utils.dart';
import 'cache.dart';
import 'error.dart';
import 'helpers.dart';
import 'options.dart';
import 'run_condition.dart';
import 'task.dart';
import 'task_run.dart';

/// Initializes the dartle library and runs the tasks selected by the user
/// (or in the provided [args]).
///
/// This method may not return if some error is found, as dartle will
/// call [exit(code)] with the appropriate error code.
Future<void> run(List<String> args,
    {@required Set<Task> tasks, Set<Task> defaultTasks = const {}}) async {
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
    final taskMap = createTaskMap(tasks);
    final executableTasks =
        await _getExecutableTasks(taskMap, taskNames, options);
    if (options.showTasks) {
      _showAll(executableTasks, tasks, defaultTasks);
    } else {
      logger.info("Executing ${executableTasks.length} task(s) out of "
          "${taskNames.length} selected task(s)");
      await _runAll(executableTasks, options);
    }

    stopWatch.stop();
    logger.info("Build succeeded in ${elapsedTime(stopWatch)}");
    exit(0);
  } on DartleException catch (e) {
    logger.error(e.message);
    logger.error("Build failed in ${elapsedTime(stopWatch)}");
    exit(e.exitCode);
  } on Exception catch (e) {
    logger.error("Unexpected error: $e");
    logger.error("Build failed in ${elapsedTime(stopWatch)}");
    exit(22);
  }
}

Future<void> _runAll(List<Task> executableTasks, Options options) async {
  final allErrors = <Exception>[];

  final results = await runTasks(executableTasks);
  final failures = results.where((r) => r.isFailure).toList(growable: false);
  final postRunFailures = await runTasksPostRun(results);

  allErrors.addAll(failures.map((f) => f.error));
  allErrors.addAll(postRunFailures);

  if (allErrors.isNotEmpty) {
    _throwAggregateErrors(allErrors);
  }
}

void _showAll(
    List<Task> executableTasks, Set<Task> tasks, Set<Task> defaultTasks) {
  final defaultSet = defaultTasks.map((t) => t.name).toSet();
  // FIXME get execution order?!
//  tasks.sort((a, b) => a.name.compareTo(b.name));
  print("Tasks declared in this build:\n");
  for (final task in tasks) {
    final desc = task.description.isEmpty ? '' : '\n      ${task.description}';
    final isDefault = defaultSet.contains(task.name) ? ' [default]' : '';
    print("  * ${task.name}${isDefault}${desc}");
  }
  print('');
  if (executableTasks.isEmpty) {
    print('No tasks would have executed with the options provided');
  } else {
    print('The following tasks would have executed, in this order:');
    executableTasks.forEach((t) => print('  * ${t.name}'));
  }
  print('');
}

Future<List<Task>> _getExecutableTasks(Map<String, TaskWithDeps> taskMap,
    List<String> requestedTasks, Options options) async {
  if (requestedTasks.isEmpty) {
    if (!options.showTasks) {
      logger.warn("No tasks were requested and no default tasks exist.");
    }
    return const [];
  }

  final mustRun = <TaskWithDeps>[];
  for (final taskNameSpec in requestedTasks) {
    final task = _findTaskByName(taskMap, taskNameSpec);
    if (task == null) {
      if (options.showTasks) {
        logger.warn("Task '$taskNameSpec' does not exist.");
        continue;
      }
      return failBuild(reason: "Unknown task: '${taskNameSpec}'") as List<Task>;
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
Future<List<Task>> getInOrderOfExecution(List<TaskWithDeps> tasks) async {
  // first of all, re-order tasks so that dependencies are in order
  tasks.sort();

  final result = <Task>[];
  final seenTasks = <String>{};

  final addTaskOnce = (Task task) async {
    if (seenTasks.add(task.name)) {
      if (await task.runCondition.shouldRun()) {
        result.add(task);
      }
    }
  };

  // de-duplicate tasks, adding their dependencies first
  for (final taskWithDeps in tasks) {
    final deps = taskWithDeps.dependencies.toList(growable: false);
    for (final dep in deps) {
      await addTaskOnce(dep);
    }
    await addTaskOnce(taskWithDeps);
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
