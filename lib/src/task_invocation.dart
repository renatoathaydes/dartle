import '_log.dart';
import '_text_helpers.dart';
import 'error.dart';
import 'options.dart';
import 'task.dart';

const taskArgumentPrefix = ':';

enum InvocationReason {
  calledByUser,
  byDefault,
  requirement,
  dependency,
  synthetic,
}

class TaskInvocation {
  final TaskWithDeps task;
  final List<String> args;
  final InvocationReason reason;
  final String _name;

  TaskInvocation(
    this.task, {
    this.args = const <String>[],
    String? name,
    this.reason = InvocationReason.calledByUser,
  }) : _name = name ?? task.name;

  /// The invocation task name (may be different from the actual task's name).
  String get name => _name;

  /// Whether this task was not directly invoked, but included by an invoked
  /// task's requirements.
  bool get byRequirement => reason == InvocationReason.requirement;

  @override
  String toString() {
    return 'TaskInvocation{task: $name, args: $args}';
  }
}

/// Parse the tasks invocation provided by the user.
///
/// Assumes all Dartle CLI options have been "consumed" already, and are not
/// included in the tasksInvocation.
List<TaskInvocation> parseInvocation(
  List<String> tasksInvocation,
  Map<String, TaskWithDeps> taskMap,
  Options options, [
  bool usingDefaultTasks = false,
]) {
  final invocations = <String, TaskInvocation>{};
  (TaskWithDeps task, String nameSpec)? current;
  var followsTask = false;
  final requiredTasks = <String>{};
  final errors = <String>{};
  var currentArgs = <String>[];

  void addInvocationOf(
    TaskWithDeps task,
    String nameSpec,
    InvocationReason reason,
  ) {
    if (invocations.containsKey(task.name)) {
      errors.add("Cannot invoke task more than once: '${task.name}'");
      return;
    }
    final isValid = task.argsValidator.validate(currentArgs);
    if (isValid) {
      invocations[task.name] = TaskInvocation(
        task,
        args: currentArgs,
        name: nameSpec,
        reason: reason,
      );
    } else {
      errors.add(
        "Invalid arguments for task '${task.name}': "
        '$currentArgs - ${task.argsValidator.helpMessage()}',
      );
    }
  }

  void addInvocationForCurrentTask() {
    if (current != null) {
      addInvocationOf(
        current.$1,
        current.$2,
        usingDefaultTasks
            ? InvocationReason.byDefault
            : InvocationReason.calledByUser,
      );
    }
  }

  for (var word in tasksInvocation) {
    if (word.startsWith(taskArgumentPrefix)) {
      if (current != null) {
        currentArgs.add(word.substring(1));
      } else if (!followsTask) {
        errors.add("Argument should follow a task: '$word'");
      }
    } else {
      followsTask = true;
      final task = _findTaskByName(taskMap, word);
      if (task == null) {
        errors.add("Task '$word' does not exist");
      } else {
        addInvocationForCurrentTask();
        current = (task, word);
        currentArgs = <String>[];
        // transitive requirements are not allowed, hence we do not recurse.
        requiredTasks.addAll(task.requirements);
      }
    }
  }

  addInvocationForCurrentTask();

  for (final name in requiredTasks.where(
    (name) => !invocations.containsKey(name),
  )) {
    logger.fine(() => "'Adding required task to invocation: '$name'");
    // null-safe: requirements are already validated elsewhere.
    addInvocationOf(taskMap[name]!, name, InvocationReason.requirement);
  }

  if (errors.isNotEmpty) {
    if (options.showInfoOnly) {
      for (var err in errors) {
        logger.severe(err);
      }
    } else {
      final message = errors.length > 1
          ? 'Several invocation problems found:\n'
                '${errors.map((err) => '  * $err').join('\n')}'
          : 'Invocation problem: ${errors.first}';
      throw DartleException(message: message);
    }
  }

  return invocations.values.toList();
}

TaskWithDeps? _findTaskByName(
  Map<String, TaskWithDeps> taskMap,
  String nameSpec,
) {
  final name = findMatchingByWords(
    nameSpec,
    taskMap.keys.toList(growable: false),
  );
  if (name == null) return null;
  return taskMap[name];
}
