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

/// Phases of [Task]s.
///
/// Tasks in each phase always run before any tasks from the next phase.
///
/// The order of built-in phases is:
/// 1. setup
/// 2. build (default)
/// 3. tearDown
///
/// Custom phases can be created as long as they use unique [index] and [name].
class TaskPhase implements Comparable<TaskPhase> {
  /// The index of this phase, used for sorting phases.
  final int index;

  /// The name of this phase.
  final String name;

  const TaskPhase._(this.index, this.name);

  /// Create or return a custom phase with the given parameters.
  ///
  /// It's an error to attempt to get a phase with an existing index but
  /// different name, or with an existing name but different index, but calling
  /// this method with the same name and index as an existing phase will return
  /// the existing phase.
  ///
  /// To get all the existing phases, use [TaskPhase.builtInPhases] for the
  /// immutable, built-in phases, or [TaskPhase.currentZoneTaskPhases] for
  /// the current [Zone]'s custom phases.
  ///
  /// See [TaskPhase.zonePhasesKey] for information on isolating task phases
  /// modifications to Dart [Zone]s.
  ///
  factory TaskPhase.custom(int index, String name) {
    final phases = currentZoneTaskPhases;
    final existingPhaseByIndex =
        phases.firstWhereOrNull((p) => p.index == index);
    final existingPhaseByName = phases.firstWhereOrNull((p) => p.name == name);
    if (existingPhaseByIndex != null &&
        existingPhaseByIndex == existingPhaseByName) {
      return existingPhaseByIndex;
    }
    if (existingPhaseByIndex != null) {
      throw DartleException(
          message: "Attempting to create new phase '$name' "
              "with existing index $index, which is used for phase "
              "'${existingPhaseByIndex.name}'");
    }
    if (existingPhaseByName != null) {
      throw DartleException(
          message: "Attempting to create new phase '$name' "
              "with existing name '$name'");
    }
    final phase = TaskPhase._(index, name);
    phases.add(phase);
    phases.sort();
    return phase;
  }

  /// Whether this phase comes before another phase.
  bool isBefore(TaskPhase other) => index < other.index;

  /// Whether this phase comes after another phase.
  bool isAfter(TaskPhase other) => index > other.index;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskPhase && index == other.index && name == other.name;

  @override
  int get hashCode => index.hashCode ^ name.hashCode;

  @override
  int compareTo(TaskPhase other) {
    return index.compareTo(other.index);
  }

  @override
  String toString() {
    return 'TaskPhase{index: $index, name: $name}';
  }

  /// Key used to register custom phases inside a Dart [Zone].
  ///
  /// It can be used to query and override the [TaskPhase]s being used in the
  /// current Zone.
  ///
  /// When registering a List, it must be mutable to allow new custom tasks
  /// being created.
  ///
  /// Use [currentZoneTaskPhases] to access the [Zone]'s phases.
  static const Symbol zonePhasesKey = #zonePhases;

  /// Get the task phases in the current [Zone], if it has been set,
  /// or the root task phases otherwise.
  ///
  /// See also [TaskPhase.zonePhasesKey].
  static List<TaskPhase> get currentZoneTaskPhases {
    final phases = Zone.current[zonePhasesKey];
    if (phases != null) {
      return phases as List<TaskPhase>;
    }
    return _rootTaskPhases;
  }

  /// The 'setup' built-in task phase.
  static const TaskPhase setup = TaskPhase._(100, 'setup');

  /// The 'build' built-in task phase.
  static const TaskPhase build = TaskPhase._(500, 'build');

  /// The 'tearDown' built-in task phase.
  static const TaskPhase tearDown = TaskPhase._(1000, 'tearDown');

  /// Get the built-in phases. The returned List is immutable.
  /// To access custom phases, use [currentZoneTaskPhases] instead.
  static final List<TaskPhase> builtInPhases = const [setup, build, tearDown];

  /// mutable task phases list at root Zone. Can be overridden with a
  /// Zone-specific List.
  static final List<TaskPhase> _rootTaskPhases = [...builtInPhases];
}

extension TaskPhaseString on TaskPhase {
  String name() => toString().substring('TaskPhase.'.length);
}

/// A Dartle task whose action is provided by user code in order to execute
/// some logic during a build run.
class Task {
  final String description;
  final RunCondition runCondition;
  final ArgsValidator argsValidator;
  final TaskPhase phase;
  Set<String> _dependsOn;
  final _NameAction _nameAction;

  Task(
    Function(List<String>) action, {
    this.description = '',
    String name = '',
    Set<String> dependsOn = const {},
    this.runCondition = const AlwaysRun(),
    this.argsValidator = const DoNotAcceptArgs(),
    this.phase = TaskPhase.build,
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
  TaskPhase get phase => _task.phase;

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
    if (phase.isBefore(other.phase)) return thisBeforeOther;
    if (phase.isAfter(other.phase)) return thisAfterOther;
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

extension TaskStatusString on TaskStatus {
  String name() => toString().substring('TaskStatus.'.length);
}

/// Task with its status, including its current invocation.
class TaskWithStatus {
  final TaskWithDeps task;
  final TaskStatus status;
  final TaskInvocation invocation;

  TaskWithStatus(this.task, this.status, this.invocation);

  bool get mustRun => status != TaskStatus.upToDate;

  @override
  String toString() {
    return 'TaskWithStatus{task: $task, status: ${status.name()}}';
  }
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
  /// dependency on tasks in this group and that it belongs to the same phase
  /// as other tasks in this group, hence it can run in parallel with
  /// the other tasks.
  bool canInclude(TaskWithDeps task) {
    for (final t in invocations.map((i) => i.task)) {
      if (t.phase.index != task.phase.index) return false;
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

/// Verify that all tasks in [taskMap] have inputs/outputs that are mutually
/// consistent.
///
/// If a task uses the outputs of another task as its inputs, then it must have
/// an explicit dependency on the other task.
///
/// Any inconsistencies will cause a [DartleException] to be thrown by
/// this method.
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

/// Verify that all tasks in [taskMap] lie in phases that are consistent with
/// their dependencies.
///
/// No task can depend on another task that belongs to a build phase that runs
/// after its own.
///
/// Tasks cannot be executed on a [Zone] that does not include its phase.
///
/// Any inconsistencies will cause a [DartleException] to be thrown by
/// this method.
Future<void> verifyTaskPhasesConsistency(
    Map<String, TaskWithDeps> taskMap) async {
  final errors = <String>{};

  // a task's dependencies must be in the same or earlier phases
  for (final task in taskMap.values) {
    task.dependencies.where((dep) => dep.phase.isAfter(task.phase)).forEach(
        (t) => errors.add("Task '${task.name}' in phase '${task.phase.name}' "
            "cannot depend on '${t.name}' in phase '${t.phase.name}'"));
  }

  if (errors.isNotEmpty) {
    throw DartleException(
        message: "The following tasks have dependency on tasks which are in an "
            "incompatible build phase:\n"
            '${errors.map((e) => '  * $e.').join('\n')}\n');
  }

  final phases = TaskPhase.currentZoneTaskPhases;
  for (final task in taskMap.values) {
    if (!phases.contains(task.phase)) {
      errors.add("Task '${task.name}' belongs to phase '${task.phase.name}'.");
    }
  }

  if (errors.isNotEmpty) {
    final phaseNames = phases.map((p) => p.name).join(', ');
    throw DartleException(
        message: "The following tasks do not belong to any of the phases in "
            "the current Dart Zone, which are $phaseNames}:\n"
            '${errors.map((e) => '  * $e.').join('\n')}\n');
  }
}
