import '_log.dart';
import '_text_helpers.dart';
import 'error.dart';
import 'options.dart';
import 'task.dart';

const taskArgumentPrefix = ':';

class TaskInvocation {
  final TaskWithDeps task;
  final List<String> args;

  final String _name;

  TaskInvocation(this.task, [this.args = const <String>[], String? name])
    : _name = name ?? task.name;

  /// The invocation task name (may be different from the actual task's name).
  String get name => _name;

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
  Options options,
) {
  final invocations = <String, TaskInvocation>{};
  TaskWithDeps? currentTask;
  var followsTask = false;
  final requiredTasks = <String>{};
  final errors = <String>{};
  var currentArgs = <String>[];

  void addInvocationOf(TaskWithDeps task) {
    if (invocations.containsKey(task.name)) {
      errors.add("Cannot invoke task more than once: '${task.name}'");
      return;
    }
    final isValid = task.argsValidator.validate(currentArgs);
    if (isValid) {
      invocations[task.name] = TaskInvocation(task, currentArgs);
    } else {
      errors.add(
        "Invalid arguments for task '${task.name}': "
        '$currentArgs - ${task.argsValidator.helpMessage()}',
      );
    }
  }

  void addInvocationForCurrentTask() {
    if (currentTask != null) {
      addInvocationOf(currentTask);
    }
  }

  for (var word in tasksInvocation) {
    if (word.startsWith(taskArgumentPrefix)) {
      if (currentTask != null) {
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
        currentTask = task;
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
    addInvocationOf(taskMap[name]!);
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
