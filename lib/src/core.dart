import 'dart:io' as io;

import 'package:meta/meta.dart';

import '_options.dart';
import 'helpers.dart';
import 'task.dart';

Future<void> run(List<String> args,
    {@required List<Task> tasks, List<Task> defaultTasks}) async {
  final taskMap = tasks.asMap().map((_, task) => MapEntry(task.name, task));
  if (args.isEmpty) {
    (defaultTasks ?? tasks).forEach(_runTask);
  } else {
    await runWithArgs(args, taskMap);
  }
}

Future<void> runWithArgs(List<String> args, Map<String, Task> taskMap) async {
  for (final arg in args) {
    final task = taskMap[arg];
    if (task == null) return failBuild(reason: "Unknown task: ${task.name}");
  }
  for (final arg in args) {
    await _runTask(taskMap[arg]);
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
