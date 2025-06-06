import 'dart:async';

import 'package:logging/logging.dart' as log;

import '_log.dart';
import '_project.dart';
import '_task_graph.dart';
import '_tasks_info.dart';
import '_text_helpers.dart';
import 'cache/cache.dart';
import 'dartle_version.g.dart';
import 'error.dart';
import 'options.dart';
import 'run_condition.dart';
import 'task.dart';
import 'task_invocation.dart';
import 'task_run.dart';

const dartleFileMissingMessage = 'Missing dartle.dart file. '
    'Please create one to be able to use Dartle.';

/// Initializes the dartle library and runs the tasks selected by the user
/// (or in the provided [args]).
///
/// This method will normally not return as Dartle will exit with the
/// appropriate code. To avoid that, set [doNotExit] to [true].
Future<void> run(List<String> args,
    {required Set<Task> tasks,
    Set<Task> defaultTasks = const {},
    bool doNotExit = false}) async {
  await checkProjectInit(doNotExit);

  await runSafely(args, doNotExit, (stopWatch, options) async {
    if (options.showHelp) {
      return print(dartleUsage);
    }
    if (options.showVersion) {
      return print('Dartle version $dartleVersion');
    }

    activateLogging(options.logLevel, colorfulLog: options.colorfulLog);

    await runBasic(tasks, defaultTasks, options, DartleCache.instance);
    stopWatch.stop();
    if (!options.showInfoOnly && options.logBuildTime) {
      logger.info(ColoredLogMessage(
          '✔ Build succeeded in ${elapsedTime(stopWatch)}', LogColor.green));
    }
  });
}

/// Run the given action in a safe try/catch block, allowing Dartle to handle
/// any errors by logging the appropriate build failure.
///
/// If [doNotExit] is `true`, then this method will not call [exit] on build
/// completion, re-throwing Exceptions. Otherwise, the process will exit with
/// 0 on success, or the appropriate error code on error.
Future<void> runSafely(List<String> args, bool doNotExit,
    FutureOr<void> Function(Stopwatch, Options) action) async {
  final stopWatch = Stopwatch()..start();
  var options = const Options();

  try {
    options = parseOptions(args);
    await action(stopWatch, options);
    if (!doNotExit) abort(0);
  } on DartleException catch (e) {
    // activate SEVERE logging in case logging was not enabled yet
    activateLogging(log.Level.SEVERE);
    logger.severe(e.message);
    if (logger.isLoggable(log.Level.FINE)) {
      _logStackTrace(e);
    }
    if (options.logBuildTime) {
      logger.severe(ColoredLogMessage(
          '✗ Build failed in ${elapsedTime(stopWatch)}', LogColor.red));
    }
    if (doNotExit) {
      rethrow;
    } else {
      abort(e.exitCode);
    }
  } on Exception catch (e, st) {
    // activate SEVERE logging in case logging was not enabled yet
    activateLogging(log.Level.SEVERE);
    logger.severe('Unexpected error', e, st);
    if (options.logBuildTime) {
      logger.severe(ColoredLogMessage(
          '✗ Build failed in ${elapsedTime(stopWatch)}', LogColor.red));
    }
    if (doNotExit) {
      rethrow;
    } else {
      abort(22);
    }
  }
}

void _logStackTrace(DartleException exception) {
  if (exception is MultipleExceptions) {
    logger.severe('Multiple stackTraces:');
    for (final exSt in exception.exceptionsAndStackTraces) {
      logger.severe('============>', exSt.exception, exSt.stackTrace);
    }
  }
}

/// Run a Dartle build with a "basic" setup.
///
/// Unlike [run], this function does not handle errors, times the build
/// or initializes the logging system.
///
/// It is only appropriate for embedding Dartle within another system.
///
/// Returns the tasks that may have been executed, grouped together into each
/// phase that could be executed in parallel (as returned by [getInOrderOfExecution]).
Future<List<ParallelTasks>> runBasic(Set<Task> tasks, Set<Task> defaultTasks,
    Options options, DartleCache cache) async {
  logger.fine(() => 'Dartle version: $dartleVersion\nOptions: $options');

  if (options.resetCache) {
    await cache.clean();
    cache.init();
  }

  var tasksInvocation = options.tasksInvocation;
  final directTasksCount = tasksInvocation
      .where((name) => !name.startsWith(taskArgumentPrefix))
      .length;
  if (directTasksCount == 0 && defaultTasks.isNotEmpty) {
    tasksInvocation = defaultTasks.map((t) => t.name).toList();
  }
  final taskMap = createTaskMap(tasks);
  final tasksAffectedByDeletion =
      await verifyTaskInputsAndOutputsConsistency(taskMap);
  await verifyTaskPhasesConsistency(taskMap);
  final executableTasks = await _getExecutableTasks(
      taskMap, tasksInvocation, options, tasksAffectedByDeletion);
  if (options.showInfoOnly) {
    print(colorize(
        '======== Showing build information only, no tasks will '
        'be executed ========\n',
        LogColor.blue));
    showTasksInfo(executableTasks, taskMap, defaultTasks, options);
  } else {
    if (logger.isLoggable(log.Level.INFO)) {
      logTasksInfo(tasks, executableTasks, options.tasksInvocation,
          directTasksCount, defaultTasks);
    }

    try {
      await _runAll(executableTasks, options);
    } finally {
      if (!options.disableCache) {
        await _cleanCache(cache,
            taskMap.keys.followedBy(const ['_compileDartleFile']).toSet());
      }
    }
  }

  return executableTasks;
}

FutureOr<void> _cleanCache(DartleCache cache, Set<String> taskNames) {
  ignoreExceptions(() {
    final stopWatch = Stopwatch()..start();
    try {
      return cache.removeNotMatching(taskNames, taskNames);
    } finally {
      logger.log(
          profile, 'Garbage-collected cache in ${elapsedTime(stopWatch)}');
    }
  });
}

Future<void> _runAll(
    List<ParallelTasks> executableTasks, Options options) async {
  final results = await runTasks(executableTasks,
      parallelize: options.parallelizeTasks,
      disableCache: options.disableCache,
      force: options.forceTasks);

  final taskErrors = results
      .map((f) => f.exceptionAndStackTrace)
      .nonNulls
      .toList(growable: false);

  if (taskErrors.isNotEmpty) {
    throw MultipleExceptions(taskErrors);
  }
}

Future<List<ParallelTasks>> _getExecutableTasks(
    Map<String, TaskWithDeps> taskMap,
    List<String> tasksInvocation,
    Options options,
    DeletionTasksByTask tasksAffectedByDeletion) async {
  if (tasksInvocation.isEmpty) {
    if (!options.showInfoOnly) {
      logger.warning('No tasks were requested and no default tasks exist.');
    }
    return const [];
  }
  final invocations = parseInvocation(tasksInvocation, taskMap, options);

  // also force tasks if the cache is disabled
  final force = options.forceTasks || options.disableCache;

  return await getInOrderOfExecution(
      invocations, force, options.showTasks, tasksAffectedByDeletion);
}

/// Get the tasks in the order that they should be executed, taking into account
/// their dependencies and phases.
///
/// To know which tasks must run, call [TaskWithStatus.mustRun] on each returned
/// task.
///
/// Notice that when a task is out-of-date, all of its dependents also become
/// out-of-date.
Future<List<ParallelTasks>> getInOrderOfExecution(
    List<TaskInvocation> invocations,
    [bool forceTasks = false,
    bool showTasks = false,
    DeletionTasksByTask tasksAffectedByDeletion = const {}]) async {
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

  Future<void> addInvocation(TaskInvocation invocation) async {
    final taskWithStatus = await _createTaskWithStatus(
        invocation, taskStatuses, forceTasks, tasksAffectedByDeletion);
    taskStatuses[invocation.name] = taskWithStatus;
    addTaskToParallelTasks(taskWithStatus);
  }

  final seenTasks = <String>{};

  for (final inv in invocations) {
    for (final dep in inv.task.dependencies) {
      if (seenTasks.add(dep.name)) await addInvocation(TaskInvocation(dep));
    }
    if (seenTasks.add(inv.name)) await addInvocation(inv);
  }

  return result;
}

Future<TaskWithStatus> _createTaskWithStatus(
  TaskInvocation invocation,
  Map<String, TaskWithStatus> taskStatuses,
  bool forceTask,
  DeletionTasksByTask tasksAffectedByDeletion,
) async {
  final task = invocation.task;
  TaskStatus status;
  if (forceTask) {
    status = TaskStatus.forced;
  } else if (task.runCondition == const AlwaysRun()) {
    status = TaskStatus.alwaysRuns;
  } else if (_isAffectedByDeletionTask(
      task, taskStatuses, tasksAffectedByDeletion)) {
    status = TaskStatus.affectedByDeletionTask;
  } else if (_anyDepMustRun(task, taskStatuses)) {
    status = TaskStatus.dependencyIsOutOfDate;
  } else if (await _shouldRun(invocation)) {
    status = TaskStatus.outOfDate;
  } else {
    status = TaskStatus.upToDate;
  }
  return TaskWithStatus(task, status, invocation);
}

bool _anyDepMustRun(TaskWithDeps task, Map<String, TaskWithStatus> statuses) {
  final mustRunDeps = task.dependencies
      .where((element) => statuses[element.name]?.mustRun ?? false);
  if (mustRunDeps.isNotEmpty) {
    logger.fine(() => "Task '${task.name}' must run because it "
        "depends on task '${mustRunDeps.first.name}' which must run");
  }
  return mustRunDeps.isNotEmpty;
}

Future<bool> _shouldRun(TaskInvocation invocation) async {
  final stopWatch = Stopwatch()..start();
  final result = await invocation.task.runCondition.shouldRun(invocation);
  if (result) {
    logger.fine(() => "Task '${invocation.name}' must run because it is "
        "out-of-date");
  }
  logger.log(
      profile,
      "Checked task '${invocation.name}'"
      ' runCondition in ${elapsedTime(stopWatch)}');
  return result;
}

bool _isAffectedByDeletionTask(
    TaskWithDeps task,
    Map<String, TaskWithStatus> taskStatuses,
    DeletionTasksByTask tasksAffectedByDeletion) {
  final deletionTasks = tasksAffectedByDeletion[task.name] ?? const {};
  for (final delTask in deletionTasks) {
    final status = taskStatuses[delTask];
    if (status?.mustRun == true) {
      logger.fine(() => "Task '${task.name}' must run because it is "
          "affected by deletion task '$delTask' which must run");
      return true;
    }
  }
  return false;
}
