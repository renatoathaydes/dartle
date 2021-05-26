import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:logging/logging.dart' as log;
import 'package:path/path.dart' as p;

import '_log.dart';
import '_task_graph.dart';
import '_utils.dart';
import 'cache/cache.dart';
import 'dartle_version.g.dart';
import 'dartlex.dart';
import 'error.dart';
import 'options.dart';
import 'run_condition.dart';
import 'task.dart';
import 'task_invocation.dart';
import 'task_run.dart';

/// Initializes the dartle library and runs the tasks selected by the user
/// (or in the provided [args]).
///
/// This method will normally not return as Dartle will exit with the
/// appropriate code. To avoid that, set [doNotExit] to [true].
Future<void> run(List<String> args,
    {required Set<Task> tasks,
    Set<Task> defaultTasks = const {},
    bool doNotExit = false}) async {
  await abortIfNotDartleProject();
  await runSafely(args, doNotExit, (stopWatch, options) async {
    if (options.showHelp) {
      return print(dartleUsage);
    }
    if (options.showVersion) {
      return print('Dartle version $dartleVersion');
    }

    activateLogging(options.logLevel, colorfulLog: options.colorfulLog);

    if (!doNotExit && p.basename(Platform.script.path) == 'dartlex') {
      await runDartlex(args, onlyIfChanged: true);
      logger.fine('dartlex did not require re-compilation, continuing...');
    }

    await _runWithoutErrorHandling(args, tasks, defaultTasks, options);
    stopWatch.stop();
    if (!options.showInfoOnly && options.logBuildTime) {
      logger.info(ColoredLogMessage(
          '✔ Build succeeded in ${elapsedTime(stopWatch)}', LogColor.green));
    }
  });
}

Future<void> abortIfNotDartleProject() async {
  final dartleFile = File('dartle.dart');
  if (await dartleFile.exists()) {
    logger.fine('Dartle file exists.');
  } else {
    logger.severe('dartle.dart file does not exist. Aborting!');
    exit(4);
  }
}

/// Run the given action in a safe try/catch block, allowing Dartle to handle
/// any errors by logging the appropriate build failure.
///
/// If [doNotExit] is `true`, then this method will not call [exit] on build
/// completion, even on failures. Otherwise, the process will exit with 0 on
/// success, or the appropriate error code on error.
Future<void> runSafely(List<String> args, bool doNotExit,
    FutureOr<Object?> Function(Stopwatch, Options) action) async {
  final stopWatch = Stopwatch()..start();
  var options = const Options();

  try {
    options = parseOptions(args);
    await action(stopWatch, options);
    if (!doNotExit) exit(0);
  } on DartleException catch (e) {
    activateLogging(log.Level.SEVERE);
    logger.severe(e.message);
    if (options.logBuildTime) {
      logger.severe(ColoredLogMessage(
          '✗ Build failed in ${elapsedTime(stopWatch)}', LogColor.red));
    }
    if (!doNotExit) exit(e.exitCode);
  } on Exception catch (e) {
    activateLogging(log.Level.SEVERE);
    logger.severe('Unexpected error: $e');
    if (options.logBuildTime) {
      logger.severe(ColoredLogMessage(
          '✗ Build failed in ${elapsedTime(stopWatch)}', LogColor.red));
    }
    if (!doNotExit) exit(22);
  }
}

Future<void> _runWithoutErrorHandling(List<String> args, Set<Task> tasks,
    Set<Task> defaultTasks, Options options) async {
  logger.fine(() => 'Dartle version: $dartleVersion');
  logger.fine(() => 'Options: $options');

  if (options.resetCache) {
    await DartleCache.instance.clean();
  }

  var tasksInvocation = options.tasksInvocation;
  final directTasksCount = tasksInvocation
      .where((name) => !name.startsWith(taskArgumentPrefix))
      .length;
  if (directTasksCount == 0 && defaultTasks.isNotEmpty) {
    tasksInvocation = defaultTasks.map((t) => t.name).toList();
  }
  final taskMap = createTaskMap(tasks);
  final executableTasks =
      await _getExecutableTasks(taskMap, tasksInvocation, options);
  if (options.showInfoOnly) {
    print('======== Showing build information only, no tasks will '
        'be executed ========\n');
    showTasksInfo(executableTasks, taskMap, defaultTasks, options);
  } else {
    if (logger.isLoggable(log.Level.INFO)) {
      String taskPhrase(int count) =>
          count == 1 ? '$count task' : '$count tasks';
      final totalTasksPhrase = taskPhrase(tasks.length);
      final requestedTasksPhrase = directTasksCount == 0
          ? taskPhrase(defaultTasks.length) + ' (default)'
          : taskPhrase(directTasksCount) + ' selected';
      final executableTasksCount =
          executableTasks.expand((t) => t.invocations).length;
      final executableTasksPhrase = taskPhrase(executableTasksCount);
      final dependentTasksCount = max(
          0,
          executableTasksCount -
              (directTasksCount == 0 ? defaultTasks.length : directTasksCount));

      logger.info('Executing $executableTasksPhrase out of a total of '
          '$totalTasksPhrase: $requestedTasksPhrase, '
          '$dependentTasksCount due to dependencies');
    }

    await _runAll(executableTasks, options);
  }
}

Future<void> _runAll(
    List<ParallelTasks> executableTasks, Options options) async {
  final allErrors = <Exception>[];

  final results =
      await runTasks(executableTasks, parallelize: options.parallelizeTasks);
  final postRunFailures = await runTasksPostRun(results);

  allErrors.addAll(results.map((f) => f.error).whereType<Exception>());
  allErrors.addAll(postRunFailures);

  if (allErrors.isNotEmpty) {
    _throwAggregateErrors(allErrors);
  }
}

Future<List<ParallelTasks>> _getExecutableTasks(
    Map<String, TaskWithDeps> taskMap,
    List<String> tasksInvocation,
    Options options) async {
  if (tasksInvocation.isEmpty) {
    if (!options.showInfoOnly) {
      logger.warning('No tasks were requested and no default tasks exist.');
    }
    return const [];
  }
  final invocations = parseInvocation(tasksInvocation, taskMap, options);

  final mustRun = <TaskInvocation>[];
  for (final invocation in invocations) {
    final task = invocation.task;
    if (options.forceTasks) {
      logger.fine("Will force execution of task '${task.name}'");
      mustRun.add(invocation);
    } else if (await task.runCondition.shouldRun(invocation)) {
      mustRun.add(invocation);
    } else {
      if (options.showTasks) {
        logger.info("Task '${task.name}' is up-to-date");
      } else {
        logger.fine("Skipping task '${task.name}' as it is up-to-date");
      }
    }
  }
  return await getInOrderOfExecution(mustRun);
}

/// Get the tasks in the order that they should be executed, taking into account
/// their dependencies.
///
/// All the tasks provided included in [invocations] will be returned, as
/// the [Task]'s [RunCondition]s are not checked. However, their dependencies'
/// [RunCondition] will be checked, and only those that should run will be
/// included in the returned list.
Future<List<ParallelTasks>> getInOrderOfExecution(
    List<TaskInvocation> invocations) async {
  // first of all, re-order tasks so that dependencies are in order
  invocations.sort((a, b) => a.task.compareTo(b.task));

  final result = <ParallelTasks>[];
  final seenTasks = <String>{};

  Future<void> addTaskOnce(
      TaskInvocation invocation, bool checkShouldRun) async {
    final task = invocation.task;
    if (seenTasks.add(task.name)) {
      if (!checkShouldRun || await task.runCondition.shouldRun(invocation)) {
        final canRunInPreviousGroup =
            result.isNotEmpty && result.last.canInclude(task);
        if (canRunInPreviousGroup) {
          result.last.invocations.add(invocation);
        } else {
          result.add(ParallelTasks()..invocations.add(invocation));
        }
      }
    }
  }

  // de-duplicate tasks, adding their dependencies first
  for (final invocation in invocations) {
    for (final dep in invocation.task.dependencies) {
      await addTaskOnce(TaskInvocation(dep), true);
    }
    await addTaskOnce(invocation, false);
  }
  return result;
}

void _throwAggregateErrors(List<Exception> errors) {
  if (errors.isEmpty) return;
  if (errors.length == 1) throw errors[0];

  var exitCode = 1;
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
