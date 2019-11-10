import 'package:collection/collection.dart';

import 'error.dart';
import 'run_condition.dart';

final _functionNamePatttern = RegExp('[a-zA-Z_0-9]+');

/// A Dartle task whose action is provided by user code in order to execute
/// some logic during a build run.
class Task {
  final String name;
  final String description;
  final Function() action;
  final RunCondition runCondition;
  final Set<String> dependsOn;

  Task(
    this.action, {
    this.description = '',
    String name = '',
    this.dependsOn = const {},
    this.runCondition = const AlwaysRun(),
  }) : this.name = _resolveName(action, name ?? '');

  static String _resolveName(Function() action, String name) {
    if (name.isEmpty) {
      final funName = "$action";
      final firstQuote = funName.indexOf("'");
      if (firstQuote > 0) {
        final match =
            _functionNamePatttern.firstMatch(funName.substring(firstQuote + 1));
        if (match != null) {
          String inferredName = match.group(0);
          // likely generated from JS lambda if it looks like 'main___closure',
          // do not accept it
          if (!inferredName.contains('___')) {
            return inferredName;
          }
        }
      }

      throw ArgumentError('Task name cannot be inferred. Either give the task '
          'a name explicitly or use a top-level function as its action');
    }
    return name;
  }

  @override
  String toString() => 'Task{name: $name}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Task &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          const SetEquality().equals(dependsOn, other.dependsOn);

  @override
  int get hashCode => name.hashCode ^ dependsOn.hashCode;
}

/// A [Task] including its transitive dependencies.
///
/// Instances of this type can be sorted in the order that they would execute,
/// according to their dependencies.
class TaskWithDeps implements Task, Comparable<TaskWithDeps> {
  final Task _task;

  /// Dependencies of this task, already sorted in the order the tasks would
  /// execute.
  final List<TaskWithDeps> dependencies;

  final Set<String> _allDeps;

  TaskWithDeps(this._task, [this.dependencies = const []])
      : _allDeps = dependencies.map((t) => t.name).toSet();

  String get name => _task.name;

  get action => _task.action;

  /// All transitive dependencies of this task.
  Set<String> get dependsOn => _allDeps;

  /// The direct dependencies of this task.
  Set<String> get directDependencies => _task.dependsOn;

  String get description => _task.description;

  RunCondition get runCondition => _task.runCondition;

  @override
  String toString() {
    return 'TaskWithDeps{task: $_task, dependencies: $dependsOn}';
  }

  @override
  int compareTo(TaskWithDeps other) {
    const thisBeforeOther = -1;
    const thisAfterOther = 1;
    if (this.dependsOn.contains(other.name)) return thisAfterOther;
    if (other.dependsOn.contains(this.name)) return thisBeforeOther;
    return 0;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskWithDeps &&
          runtimeType == other.runtimeType &&
          _task == other._task &&
          const ListEquality().equals(dependencies, other.dependencies);

  @override
  int get hashCode => _task.hashCode ^ dependencies.hashCode;
}

class ParallelTasks {
  final List<TaskWithDeps> tasks = [];

  @override
  String toString() => 'ParallelTasks{$tasks}';

  /// Returns true the given task can be included in this group of tasks.
  ///
  /// If a task can be included, it means that it does not have any
  /// dependency on tasks in this group, hence it can run in parallel with
  /// the other tasks.
  bool canInclude(TaskWithDeps task) {
    for (final t in tasks) {
      if (t.dependsOn.contains(task.name)) return false;
      if (task.dependsOn.contains(t.name)) return false;
    }
    return true;
  }
}

/// Create a [Map] from the name of a task to the corresponding [TaskWithDeps].
///
/// The transitive dependencies of a task are resolved, so that each returned
/// [TaskWithDeps] knows every dependency it has, not only their directly
/// declared dependencies.
Map<String, TaskWithDeps> createTaskMap(Iterable<Task> tasks) {
  final tasksByName = tasks
      .toList(growable: false)
      .asMap()
      .map((_, task) => MapEntry(task.name, task));
  final result = <String, TaskWithDeps>{};
  tasksByName.forEach((name, _) {
    _collectTransitiveDependencies(name, tasksByName, result, [], '');
  });
  return result;
}

void _collectTransitiveDependencies(
    String taskName,
    Map<String, Task> tasksByName,
    Map<String, TaskWithDeps> result,
    List<String> visited,
    String ind) {
  if (result.containsKey(taskName)) return;

  final task = tasksByName[taskName];
  if (task == null) {
    visited.add(taskName);
    throw DartleException(
        message: "Task with name '$taskName' does not exist "
            "(dependency path: [${visited.join(' -> ')}])");
  }
  if (visited.contains(taskName)) {
    visited.add(taskName);
    throw DartleException(
        message: "Task dependency cycle detected: [${visited.join(' -> ')}]");
  }
  visited.add(taskName);

  final dependencies = <TaskWithDeps>[];
  for (final dep in task.dependsOn) {
    _collectTransitiveDependencies(
        dep, tasksByName, result, visited, ind + '  ');
    final depTask = result[dep];
    if (depTask == null) {
      // should never happen!!
      throw DartleException(
          message: 'Cannot resolve dependencies of task $dep');
    }
    _taskWithTransitiveDeps(depTask, dependencies);
  }
  dependencies.sort();
  result[taskName] = TaskWithDeps(task, dependencies);
}

void _taskWithTransitiveDeps(TaskWithDeps task, List<TaskWithDeps> result) {
  for (final dep in task.dependencies) {
    _taskWithTransitiveDeps(dep, result);
  }
  result.add(task);
}
