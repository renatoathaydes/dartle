import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:logging/logging.dart' as log;

import '_log.dart';
import '_task_graph.dart';
import '_utils.dart';
import 'cache/cache.dart';
import 'dartle_version.g.dart';
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
/// completion, re-throwing Exceptions. Otherwise, the process will exit with
/// 0 on success, or the appropriate error code on error.
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
    if (doNotExit) {
      rethrow;
    } else {
      exit(e.exitCode);
    }
  } on Exception catch (e) {
    activateLogging(log.Level.SEVERE);
    logger.severe('Unexpected error: $e');
    if (options.logBuildTime) {
      logger.severe(ColoredLogMessage(
          '✗ Build failed in ${elapsedTime(stopWatch)}', LogColor.red));
    }
    if (doNotExit) {
      rethrow;
    } else {
      exit(22);
    }
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
      String taskPhrase(int count,
              [String singular = 'task', String plural = 'tasks']) =>
          count == 1 ? '$count $singular' : '$count $plural';
      final totalTasksPhrase = taskPhrase(tasks.length);
      final requestedTasksPhrase = directTasksCount == 0
          ? taskPhrase(defaultTasks.length) + ' (default)'
          : taskPhrase(directTasksCount) + ' selected';
      final executableTasksCount = executableTasks
          .map((t) => t.mustRunCount)
          .fold<int>(0, (a, b) => a + b);
      final executableTasksPhrase = taskPhrase(executableTasksCount);
      final dependentTasksCount = max(
          0,
          executableTasksCount -
              (directTasksCount == 0 ? defaultTasks.length : directTasksCount));
      final dependenciesPhrase = dependentTasksCount == 0
          ? ''
          : ', ' +
              taskPhrase(dependentTasksCount, 'dependency', 'dependencies');
      final upToDateCount = executableTasks
          .map((t) => t.tasks.length - t.mustRunCount)
          .fold<int>(0, (a, b) => a + b);
      final upToDatePhrase =
          upToDateCount > 0 ? ', $upToDateCount up-to-date' : '';

      logger.info('Executing $executableTasksPhrase out of a total of '
          '$totalTasksPhrase: $requestedTasksPhrase'
          '$dependenciesPhrase$upToDatePhrase');
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

  return await getInOrderOfExecution(
      invocations, options.forceTasks, options.showTasks);
}

/// Get the tasks in the order that they should be executed, taking into account
/// their dependencies.
///
/// To know which tasks must run, call [TaskWithStatus.mustRun] on each returned
/// task.
///
/// Notice that when a task is out-of-date, all of its dependents also become
/// out-of-date.
Future<List<ParallelTasks>> getInOrderOfExecution(
    List<TaskInvocation> invocations,
    [bool forceTasks = false,
    bool showTasks = false]) async {
  // first of all, re-order tasks so that dependencies are in order
  invocations.sort((a, b) => a.task.compareTo(b.task));

  final result = <ParallelTasks>[];

  void addTaskToParallelTasks(TaskWithStatus taskWithStatus) {
    final canRunInPreviousGroup =
        result.isNotEmpty && result.last.canInclude(taskWithStatus.task);
    if (canRunInPreviousGroup) {
      result.last.add(taskWithStatus);
    } else {
      result.add(ParallelTasks()..add(taskWithStatus));
    }
  }

  final taskStatuses = <String, TaskWithStatus>{};
  final seenTasks = <String>{};

  for (final inv in invocations) {
    for (final dep in inv.task.dependencies) {
      if (seenTasks.add(dep.name)) {
        final invocation = TaskInvocation(dep);
        final taskWithStatus =
            await _createTaskWithStatus(invocation, taskStatuses, false);
        taskStatuses[dep.name] = taskWithStatus;
        addTaskToParallelTasks(taskWithStatus);
      }
    }
    if (seenTasks.add(inv.name)) {
      final taskWithStatus =
          await _createTaskWithStatus(inv, taskStatuses, forceTasks);
      taskStatuses[inv.name] = taskWithStatus;
      addTaskToParallelTasks(taskWithStatus);
    }
  }

  return result;
}

bool _anyDepMustRun(TaskWithDeps task, Map<String, TaskWithStatus> statuses) {
  return task.dependencies
      .any((element) => statuses[element.name]?.mustRun ?? false);
}

Future<TaskWithStatus> _createTaskWithStatus(
  TaskInvocation invocation,
  Map<String, TaskWithStatus> taskStatuses,
  bool forceTask,
) async {
  final task = invocation.task;
  TaskStatus status;
  if (forceTask) {
    status = TaskStatus.forced;
  } else if (task.runCondition == const AlwaysRun()) {
    status = TaskStatus.alwaysRuns;
  } else if (_anyDepMustRun(task, taskStatuses)) {
    status = TaskStatus.dependencyIsOutOfDate;
  } else if (await task.runCondition.shouldRun(invocation)) {
    status = TaskStatus.outOfDate;
  } else {
    status = TaskStatus.upToDate;
  }
  return TaskWithStatus(task, status, invocation);
}

void _throwAggregateErrors(List<Exception> errors) {
  if (errors.isEmpty) return;
  if (errors.length == 1) throw errors[0];

  var exitCode = 1;
  for (final dartleException in errors.whereType<DartleException>()) {
    exitCode = dartleException.exitCode;
    break;
  }
  // TODO use MultipleExceptions and move this code to exception handler
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
