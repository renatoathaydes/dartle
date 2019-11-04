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
}

/// A [Task] including its transitive dependencies.
///
/// Instances of this type can be sorted in the order that they would execute,
/// according to their dependencies.
class TaskWithDeps implements Task, Comparable<TaskWithDeps> {
  final Task _task;
  final List<TaskWithDeps> dependencies;

  TaskWithDeps(this._task, [this.dependencies = const []]);

  String get name => _task.name;

  get action => _task.action;

  Set<String> get dependsOn => dependencies.map((t) => t.name).toSet();

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
  tasksByName.forEach((name, task) {
    result[name] = _withTransitiveDependencies(name, tasksByName);
  });
  return result;
}

TaskWithDeps _withTransitiveDependencies(
    String taskName, Map<String, Task> tasksByName,
    [List<String> visited = const []]) {
  final task = tasksByName[taskName];
  if (task == null) {
    // this must never happen, when 'visited' is empty the
    // given taskName should be certain to exist
    if (visited.isEmpty) {
      throw "Task '$taskName' does not exist";
    }
    throw DartleException(
        message: "Task '${visited.last}' depends on '${taskName}', "
            "which does not exist.");
  }
  visited = [...visited, taskName];
  return TaskWithDeps(
      task,
      task.dependsOn
          .map(
              (name) => _withTransitiveDependencies(name, tasksByName, visited))
          .toList());
}
