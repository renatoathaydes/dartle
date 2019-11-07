import 'dart:io';

import 'options.dart';
import 'task.dart';

void showTasksInfo(List<Task> executableTasks, Set<Task> tasks,
    Set<Task> defaultTasks, Options options) {
  if (options.showTasks) {
    showAll(executableTasks, tasks, defaultTasks);
  }
  if (options.showTaskGraph) {
    showTaskGraph(executableTasks, tasks, defaultTasks);
  }
}

void showAll(
    List<Task> executableTasks, Set<Task> tasks, Set<Task> defaultTasks) {
  final defaultSet = defaultTasks.map((t) => t.name).toSet();
  final taskList = tasks.toList(growable: false);
  taskList.sort((t1, t2) => t1.name.compareTo(t2.name));
  print("Tasks declared in this build:\n");
  for (final task in taskList) {
    final desc = task.description.isEmpty ? '' : '\n      ${task.description}';
    final isDefault = defaultSet.contains(task.name) ? ' [default]' : '';
    print("  * ${task.name}${isDefault}${desc}");
  }
  print('');
  if (executableTasks.isEmpty) {
    print('No tasks were selected to run.');
  } else {
    print('The following tasks were selected to run, in order:\n');
    stdout.write('  ');
    print(executableTasks.map((t) => t.name).join(' -> '));
  }
  print('');
}

void showTaskGraph(
    List<Task> executableTasks, Set<Task> tasks, Set<Task> defaultTasks) {
  print("\nTASK GRAPH: TODO\n");
}
