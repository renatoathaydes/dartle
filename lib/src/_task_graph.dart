import 'dart:io';

import 'package:collection/collection.dart';
import 'package:logging/logging.dart';

import '_log.dart';
import 'options.dart';
import 'run_condition.dart';
import 'task.dart';

void showTasksInfo(
    List<ParallelTasks> executableTasks,
    Map<String, TaskWithDeps> taskMap,
    Set<Task> defaultTasks,
    Options options) {
  if (options.showTasks) {
    showAll(executableTasks, taskMap, defaultTasks);
    stdout.writeln();
  }
  if (options.showTaskGraph) {
    showTaskGraph(executableTasks, taskMap, defaultTasks);
    stdout.writeln();
  }

  showExecutableTasks(executableTasks);
  stdout.writeln();
}

void showAll(List<ParallelTasks> executableTasks, Map<String, Task> taskMap,
    Set<Task> defaultTasks) {
  final defaultSet = defaultTasks.map((t) => t.name).toSet();
  final taskList = taskMap.values.toList()
    ..sort((t1, t2) => t1.name.compareTo(t2.name));
  final tasksByName = lastBy(executableTasks.expand((t) => t.tasks),
      (TaskWithStatus t) => t.task.name);

  void show(TaskPhase phase, Iterable<Task> taskList) {
    print(colorize(
        style('==> ${phase.name.capitalized} Phase:', LogStyle.italic),
        LogColor.blue));
    if (taskList.isEmpty) {
      print('  No tasks in this phase.');
    } else {
      final verbose = logger.isLoggable(Level.FINE);
      for (final task in taskList) {
        final desc =
            task.description.isEmpty ? '' : '\n      ${task.description}';
        final io = !verbose || task.runCondition == const AlwaysRun()
            ? ''
            : '\n      runCondition: ${task.runCondition}';
        final args = verbose && (task.argsValidator is! DoNotAcceptArgs)
            ? '\n      taskArguments: ${task.argsValidator.helpMessage()}'
            : '';
        final isDefault = defaultSet.contains(task.name)
            ? style(' [default]', LogStyle.dim)
            : '';
        final status = (tasksByName[task.name]?.status).describe();
        print('  * ${style(task.name, LogStyle.bold)}$isDefault$status'
            '$desc$io$args');
      }
    }
  }

  print('Tasks declared in this build:\n');

  for (final phase in TaskPhase.currentZoneTaskPhases) {
    show(phase, taskList.where((task) => task.phase == phase));
  }
}

extension StatusDescribe on TaskStatus? {
  String describe() {
    switch (this) {
      case null:
        return '';
      case TaskStatus.upToDate:
        return colorize(' [up-to-date]', LogColor.green);
      case TaskStatus.alwaysRuns:
        return style(' [always-runs]', LogStyle.dim);
      case TaskStatus.affectedByDeletionTask:
        return colorize(' [affected-by-deletion-task]', LogColor.yellow);
      case TaskStatus.dependencyIsOutOfDate:
        return colorize(' [dependency-out-of-date]', LogColor.yellow);
      case TaskStatus.outOfDate:
        return colorize(' [out-of-date]', LogColor.yellow);
      case TaskStatus.forced:
        return colorize(' [forced]', LogColor.yellow);
    }
  }
}

void showTaskGraph(List<ParallelTasks> executableTasks,
    Map<String, TaskWithDeps> taskMap, Set<Task> defaultTasks) {
  print('Tasks Graph:\n');

  final seenTasks = <String>{};

  void printTasks(List<TaskWithDeps> tasks, String indent, bool topLevel) {
    var i = 0;
    for (final task in tasks) {
      final firstTask = i == 0;
      final lastTask = ++i == tasks.length;
      final notSeenYet = seenTasks.add(task.name);
      if (notSeenYet || !topLevel) {
        final branch = topLevel
            ? '-'
            : lastTask
                ? '\\---'
                : firstTask
                    ? '+---'
                    : '|---';
        stdout.write('$indent$branch ${task.name}');
      }
      if (notSeenYet) {
        stdout.writeln();
        printTasks(
            task.directDependencies.map((t) => taskMap[t]!).toList()
              ..sort((t1, t2) => t1.name.compareTo(t2.name)),
            topLevel ? '  ' : indent + (lastTask ? '     ' : '|     '),
            false);
      } else if (!topLevel) {
        stdout.writeln(task.dependencies.isNotEmpty ? ' ...' : '');
      }
    }
  }

  final taskList = taskMap.values.toList()
    ..sort((t1, t2) => t1.name.compareTo(t2.name));

  printTasks(taskList, '', true);
}

void showExecutableTasks(List<ParallelTasks> executableTasks) {
  if (executableTasks.isEmpty) {
    print('No tasks were selected to run.');
  } else {
    print('The following tasks were selected to run, in order:\n');
    var indentation = '  ';
    for (final pTasks in executableTasks) {
      for (final task in pTasks.tasks) {
        stdout.write(indentation);
        stdout.writeln(task.invocation.name);
      }
      indentation += '    ';
    }
  }
}

extension _CapitalString on String {
  String get capitalized {
    if (isEmpty) return '';
    final c = this[0];
    return '${c.toUpperCase()}${substring(1)}';
  }
}
