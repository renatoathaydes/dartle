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
  TaskWithDeps currentTask;
  bool followsTask = false;
  final errors = <String>[];
  var currentArgs = <String>[];

  for (String word in tasksInvocation) {
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
        if (currentTask != null) {
          invocations.add(TaskInvocation(currentTask, currentArgs));
        }
        currentTask = task;
        currentArgs = <String>[];
      }
    }
  }

  if (currentTask != null) {
    invocations.add(TaskInvocation(currentTask, currentArgs));
  }

  if (errors.isNotEmpty) {
    if (options.showInfoOnly) {
      errors.forEach((err) => logger.warn(err));
    } else {
      final message = errors.length > 1
          ? 'Several invocation problems found:\n' +
              errors.map((err) => "  * $err").join('\n')
          : 'Invocation problem: ${errors[0]}';
      throw DartleException(message: message);
    }
  }

  return invocations;
}

TaskWithDeps _findTaskByName(
    Map<String, TaskWithDeps> taskMap, String nameSpec) {
  final name =
      findMatchingByWords(nameSpec, taskMap.keys.toList(growable: false));
  if (name == null) return null;
  return taskMap[name];
}
