import 'dart:io' as io;

import 'package:dartle/dartle.dart';
import 'package:meta/meta.dart';

import '_options.dart';
import 'helpers.dart';

final _functionNamePatttern = RegExp('[a-zA-Z_0-9]+');

class Task {
  final String name;
  final String description;
  final Function() action;

  Task(this.action, {this.description = '', String name})
      : this.name = _resolveName(action, name);

  static String _resolveName(Function() action, String name) {
    if (name == null || name.isEmpty) {
      final funName = "$action";
      final firstQuote = funName.indexOf("'");
      if (firstQuote > 0) {
        final match =
            _functionNamePatttern.firstMatch(funName.substring(firstQuote + 1));
        if (match != null) {
          return match.group(0);
        }
      }

      throw ArgumentError('Task name cannot be inferred. Either give the task '
          'a name explicitly or use a top-level function as its action');
    }
    return name;
  }

  @override
  String toString() => 'Task{name: $name}';
}

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
