import 'dart:io' as io;

import 'package:meta/meta.dart';

import '_options.dart';
import 'helpers.dart';
import 'task.dart';

Future<void> run(List<String> args,
    {@required List<Task> tasks, List<Task> defaultTasks}) async {
  final taskNames = parseOptionsAndGetTasks(args);
  final taskMap = tasks.asMap().map((_, task) => MapEntry(task.name, task));
  if (taskNames.isEmpty) {
    (defaultTasks ?? tasks).forEach(_runTask);
  } else {
    await _runTasks(taskNames, taskMap);
  }
}

Future<void> _runTasks(List<String> tasks, Map<String, Task> taskMap) async {
  for (final taskName in tasks) {
    final task = taskMap[taskName];
    if (task == null) return failBuild(reason: "Unknown task: ${task.name}");
  }
  for (final taskName in tasks) {
    await _runTask(taskMap[taskName]);
  }
}

Future<void> _runTask(Task task) async {
  if (isLogEnabled(LogLevel.info)) {
    io.stdout.write("Running task: ${task.name}");
  }
  try {
    await task.action();
  } on Exception catch (e) {
    failBuild(reason: "Task ${task.name} failed due to $e");
  } finally {
    print('');
  }
}
