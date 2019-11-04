import 'dart:async';

import 'package:meta/meta.dart';

import '_log.dart';
import '_task.dart';
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

Map<String, TaskWithDeps> createTaskMap(Iterable<Task> tasks) {
  final tasksByName = tasks
      .toList(growable: false)
      .asMap()
      .map((_, task) => MapEntry(task.name, task));
  final result = <String, TaskWithDeps>{};
  tasksByName.forEach((name, task) {
    result[name] = _withTransitiveDependencies(name, tasksByName);
  });
  return result;
}

TaskWithDeps _withTransitiveDependencies(
    String taskName, Map<String, Task> tasksByName,
    [List<String> visited = const []]) {
  final task = tasksByName[taskName];
  if (task == null) {
    // this must never happen, when 'visited' is empty the
    // given taskName should be certain to exist
    if (visited.isEmpty) {
      throw "Task '$taskName' does not exist";
    }
    throw DartleException(
        message: "Task '${visited.last}' depends on '${taskName}', "
            "which does not exist.");
  }
  visited = [...visited, taskName];
  return TaskWithDeps(
      task,
      task.dependsOn
          .map(
              (name) => _withTransitiveDependencies(name, tasksByName, visited))
          .toSet());
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
  return expandToOrderOfExecution(mustRun);
}

List<Task> expandToOrderOfExecution(List<TaskWithDeps> tasks) {
  // first of all, re-order tasks so that dependencies are in order
  tasks.sort();
  final result = <Task>[];
  final seenTasks = <String>{};
  for (final taskWithDeps in tasks) {
    for (final dep in taskWithDeps.dependencies) {
      if (seenTasks.add(dep.name)) {
        result.add(dep);
      }
    }
    if (seenTasks.add(taskWithDeps.name)) {
      result.add(taskWithDeps);
    }
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
