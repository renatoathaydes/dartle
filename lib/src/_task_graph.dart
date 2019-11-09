import 'dart:io';

import 'options.dart';
import 'task.dart';

void showTasksInfo(
    List<TaskWithDeps> executableTasks,
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

void showAll(List<TaskWithDeps> executableTasks, Map<String, Task> taskMap,
    Set<Task> defaultTasks) {
  final defaultSet = defaultTasks.map((t) => t.name).toSet();
  final taskList = taskMap.values.toList()
    ..sort((t1, t2) => t1.name.compareTo(t2.name));
  print("Tasks declared in this build:\n");
  for (final task in taskList) {
    final desc = task.description.isEmpty ? '' : '\n      ${task.description}';
    final isDefault = defaultSet.contains(task.name) ? ' [default]' : '';
    print("  * ${task.name}${isDefault}${desc}");
  }
}

void showTaskGraph(List<Task> executableTasks,
    Map<String, TaskWithDeps> taskMap, Set<Task> defaultTasks) {
  print("Tasks Graph:\n");

  final seenTasks = <String>{};

  void printTasks(List<TaskWithDeps> tasks, String indent, bool topLevel) {
    var i = 0;
    for (final task in tasks) {
      final firstTask = i == 0;
      final lastTask = ++i == tasks.length;
      final notSeenYet = seenTasks.add(task.name);
      if (notSeenYet || !topLevel) {
        final branch =
            topLevel ? '-' : lastTask ? '\\---' : firstTask ? '+---' : '|---';
        stdout.write("$indent$branch ${task.name}");
      }
      if (notSeenYet) {
        stdout.writeln();
        printTasks(
            task.directDependencies.map((t) => taskMap[t]).toList()
              ..sort((t1, t2) => t1.name.compareTo(t2.name)),
            topLevel ? '  ' : indent + (lastTask ? '     ' : '|     '),
            false);
      } else if (!topLevel) {
        stdout.writeln(task.dependsOn.isNotEmpty ? " ..." : '');
      }
    }
  }

  final taskList = taskMap.values.toList()
    ..sort((t1, t2) => t1.name.compareTo(t2.name));

  printTasks(taskList, '', true);
}

void showExecutableTasks(List<TaskWithDeps> executableTasks) {
  if (executableTasks.isEmpty) {
    print('No tasks were selected to run.');
  } else {
    print('The following tasks were selected to run, in order:\n');
    stdout.write('  ');
    print(executableTasks.map((t) => t.name).join(' -> '));
  }
}
