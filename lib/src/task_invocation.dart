import '_log.dart';
import '_utils.dart';
import 'error.dart';
import 'options.dart';
import 'task.dart';

const taskArgumentPrefix = ':';

class TaskInvocation {
  final TaskWithDeps task;
  final List<String> args;

  TaskInvocation(this.task, [this.args = const <String>[]]);

  String get name => task.name;

  @override
  String toString() {
    return 'TaskInvocation{task: ${task.name}, args: $args}';
  }
}

/// Parse the tasks invocation provided by the user.
///
/// Assumes all Dartle CLI options have been "consumed" already, and are not
/// included in the tasksInvocation.
List<TaskInvocation> parseInvocation(List<String> tasksInvocation,
    Map<String, TaskWithDeps> taskMap, Options options) {
  final invocations = <TaskInvocation>[];
  TaskWithDeps? currentTask;
  var followsTask = false;
  final errors = <String>[];
  var currentArgs = <String>[];

  void addCurrentInvocation() {
    if (currentTask != null) {
      final isValid = currentTask.argsValidator.validate(currentArgs);
      if (isValid) {
        invocations.add(TaskInvocation(currentTask, currentArgs));
      } else {
        errors.add("Invalid arguments for task '${currentTask.name}': "
            '$currentArgs - ${currentTask.argsValidator.helpMessage()}');
      }
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
        addCurrentInvocation();
        currentTask = task;
        currentArgs = <String>[];
      }
    }
  }

  addCurrentInvocation();

  if (errors.isNotEmpty) {
    if (options.showInfoOnly) {
      errors.forEach((err) => logger.severe(err));
    } else {
      final message = errors.length > 1
          ? 'Several invocation problems found:\n' +
              errors.map((err) => '  * $err').join('\n')
          : 'Invocation problem: ${errors[0]}';
      throw DartleException(message: message);
    }
  }

  return invocations;
}

TaskWithDeps? _findTaskByName(
    Map<String, TaskWithDeps> taskMap, String nameSpec) {
  final name =
      findMatchingByWords(nameSpec, taskMap.keys.toList(growable: false));
  if (name == null) return null;
  return taskMap[name];
}
