import 'dart:async';

import 'package:collection/collection.dart';

import 'error.dart';
import 'file_collection.dart';
import 'run_condition.dart';
import 'task_invocation.dart';

final _functionNamePatttern = RegExp('[a-zA-Z_0-9]+');

class _NameAction {
  final String name;
  final Function(List<String>) action;
  final bool isActionTopLevelFunction;

  _NameAction(this.name, this.action, this.isActionTopLevelFunction);
}

_NameAction _resolveNameAction(Function(List<String>) action, String name) {
  var isTopLevelFunction = false;
  final funName = '$action';
  final firstQuote = funName.indexOf("'");
  if (firstQuote > 0) {
    final match =
        _functionNamePatttern.firstMatch(funName.substring(firstQuote + 1));
    if (match != null) {
      final inferredName = match.group(0) ?? '';
      // likely generated from JS lambda if it looks like 'main___closure',
      // do not accept it
      if (!inferredName.contains('___')) {
        if (name.isEmpty) name = inferredName;
        isTopLevelFunction = true;
      }
    }
  }

  if (name.isEmpty) {
    throw ArgumentError('Task name cannot be inferred. Either give the task '
        'a name explicitly or use a top-level function as its action');
  }

  return _NameAction(name, action, isTopLevelFunction);
}

/// A Dartle task whose action is provided by user code in order to execute
/// some logic during a build run.
class Task {
  final String description;
  final RunCondition runCondition;
  final ArgsValidator argsValidator;
  Set<String> _dependsOn;
  final _NameAction _nameAction;

  Task(
    Function(List<String>) action, {
    this.description = '',
    String name = '',
    Set<String> dependsOn = const {},
    this.runCondition = const AlwaysRun(),
    this.argsValidator = const DoNotAcceptArgs(),
  })  : _nameAction = _resolveNameAction(action, name),
        _dependsOn = dependsOn;

  /// The name of this task.
  String get name => _nameAction.name;

  /// Add dependencies on other tasks.
  ///
  /// This method must be called before Dartle starts running a build.
  void dependsOn(Set<String> taskNames) {
    _dependsOn = {...taskNames, ..._dependsOn};
  }

  /// The action this task performs.
  ///
  /// This function is meant to be called by Dartle, so that certain guarantees
  /// (parallelism, dependencies between tasks) can be held.
  Function(List<String> args) get action => _nameAction.action;

  /// Whether this task may run in parallel with others inside [Isolate]s.
  ///
  /// Even if this getter returns false, this task may still run asynchronously
  /// with other tasks on the same Isolate... to avoid that, impose dependencies
  /// between tasks.
  ///
  /// By default, this method only returns true if this Task's [action] is a
  /// top-level function. If [action] is not a top-level function, this method
  /// must return false as in that case, the [action] cannot be run in
  /// an [Isolate].
  bool get isParallelizable => _nameAction.isActionTopLevelFunction;

  @override
  String toString() => 'Task{name: $name}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Task &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          const SetEquality().equals(_dependsOn, other._dependsOn);

  @override
  int get hashCode => name.hashCode ^ _dependsOn.hashCode;
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

  TaskWithDeps(this._task, [this.dependencies = const <TaskWithDeps>[]])
      : _allDeps = dependencies.map((t) => t.name).toSet();

  @override
  _NameAction get _nameAction => _task._nameAction;

  @override
  String get name => _task.name;

  @override
  Function(List<String>) get action => _task.action;

  @override
  bool get isParallelizable => _task.isParallelizable;

  /// All transitive dependencies of this task.
  @override
  Set<String> get _dependsOn => _allDeps;

  /// The direct dependencies of this task.
  Set<String> get directDependencies => _task._dependsOn;

  @override
  String get description => _task.description;

  @override
  RunCondition get runCondition => _task.runCondition;

  @override
  ArgsValidator get argsValidator => _task.argsValidator;

  @override
  String toString() {
    return 'TaskWithDeps{task: $_task, dependencies: $_dependsOn}';
  }

  @override
  int compareTo(TaskWithDeps other) {
    const thisBeforeOther = -1;
    const thisAfterOther = 1;
    if (_dependsOn.contains(other.name)) return thisAfterOther;
    if (other._dependsOn.contains(name)) return thisBeforeOther;
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

  @override
  set _dependsOn(Set<String> __dependsOn) {
    throw UnsupportedError(
        'cannot modify dependencies of task after build is running');
  }

  @override
  void dependsOn(Set<String> taskNames) {
    throw UnsupportedError(
        'cannot modify dependencies of task after build is running');
  }
}

/// Status of a task.
enum TaskStatus {
  upToDate,
  alwaysRuns,
  dependencyIsOutOfDate,
  outOfDate,
  forced
}

/// Task with its status, including its current invocation.
class TaskWithStatus {
  final TaskWithDeps task;
  final TaskStatus status;
  final TaskInvocation invocation;

  TaskWithStatus(this.task, this.status, this.invocation);

  bool get mustRun => status != TaskStatus.upToDate;
}

class ParallelTasks {
  final List<TaskWithStatus> tasks = [];

  List<TaskInvocation> get invocations =>
      tasks.map((t) => t.invocation).toList();

  int get mustRunCount => tasks.where((t) => t.mustRun).length;

  int get upToDateCount => tasks.where((t) => !t.mustRun).length;

  int get length => tasks.length;

  void add(TaskWithStatus taskWithStatus) {
    tasks.add(taskWithStatus);
  }

  @override
  String toString() => 'ParallelTasks{tasks=$tasks}';

  /// Returns true the given task can be included in this group of tasks.
  ///
  /// If a task can be included, it means that it does not have any
  /// dependency on tasks in this group, hence it can run in parallel with
  /// the other tasks.
  bool canInclude(TaskWithDeps task) {
    for (final t in invocations.map((i) => i.task)) {
      if (t._dependsOn.contains(task.name)) return false;
      if (task._dependsOn.contains(t.name)) return false;
    }
    return true;
  }
}

/// Validator of arguments passed to a [Task].
mixin ArgsValidator {
  /// Validate the given [args], returning true if the arguments are valid,
  /// false otherwise.
  bool validate(List<String> args);

  /// Message explaining what arguments are expected.
  String helpMessage();
}

/// An [ArgsValidator] which does not accept any arguments.
class DoNotAcceptArgs with ArgsValidator {
  const DoNotAcceptArgs();

  @override
  String helpMessage() => 'no arguments are expected';

  @override
  bool validate(List<String> args) => args.isEmpty;
}

/// An [ArgsValidator] which accepts anything.
class AcceptAnyArgs with ArgsValidator {
  const AcceptAnyArgs();

  @override
  String helpMessage() => 'all arguments are accepted';

  @override
  bool validate(List<String> args) => true;
}

/// Validates the the number of arguments passed to a [Task].
class ArgsCount with ArgsValidator {
  final int _min;
  final int _max;

  const ArgsCount.count(int count)
      : _min = count,
        _max = count;

  const ArgsCount.range({required int min, required int max})
      : _min = min,
        _max = max;

  @override
  String helpMessage() => _min == _max
      ? "exactly $_min argument${_min == 1 ? ' is' : 's are'} expected"
      : 'between $_min and $_max arguments expected';

  @override
  bool validate(List<String> args) =>
      _min <= args.length && args.length <= _max;
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
  for (final dep in task._dependsOn) {
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

Future<void> verifyTaskInputsAndOutputsConsistency(
    Map<String, TaskWithDeps> taskMap) async {
  final inputsByTask = <TaskWithDeps, FileCollection>{};
  final outputsByTask = <TaskWithDeps, FileCollection>{};
  for (var task in taskMap.values) {
    final rc = task.runCondition;
    if (rc is FilesCondition) {
      inputsByTask[task] = rc.inputs;
      outputsByTask[task] = rc.outputs;
    }
  }

  final errors = <String>{};

  // a task's inputs may only include another's outputs if it depends on it
  inputsByTask.forEach((task, ins) {
    outputsByTask.forEach((otherTask, otherOuts) {
      if (task.dependencies.contains(otherTask)) return;
      final intersectInsOuts = ins.intersection(otherOuts);
      if (intersectInsOuts.inclusions.isNotEmpty) {
        errors.add("Task '${task.name}' must dependOn '${otherTask.name}' "
            '(clashing outputs: ${intersectInsOuts.inclusions})');
      }
    });
  });

  if (errors.isNotEmpty) {
    throw DartleException(
        message:
            "The following tasks have implicit dependencies due to their inputs depending on other tasks' outputs:\n"
            '${errors.map((e) => '  * $e.').join('\n')}\n\n'
            'Please add the dependencies explicitly.');
  }
}
