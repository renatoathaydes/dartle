import 'package:collection/collection.dart' show IterableIntegerExtension;

import '_log.dart';
import 'task.dart';

int computeDependenciesCount(
    {required int invoked,
    required int defaults,
    required int executables,
    required int upToDate}) {
  final total = executables + upToDate;
  final askedFor = (invoked == 0) ? defaults : invoked;
  return total - askedFor;
}

void logTasksInfo(
    Set<Task> tasks,
    List<ParallelTasks> executableTasks,
    List<String> tasksInvocation,
    int directTasksCount,
    Set<Task> defaultTasks) {
  if (directTasksCount == 0 && defaultTasks.isEmpty) {
    return;
  }

  final runnableTasksCount = executableTasks.map((t) => t.mustRunCount).sum;

  if (runnableTasksCount == 0) {
    return logger.info(
        const ColoredLogMessage('Everything is up-to-date!', LogColor.green));
  }

  final totalTasksCount = tasks.length;
  final upToDateCount = executableTasks.map((t) => t.upToDateCount).sum;
  final dependenciesCount = computeDependenciesCount(
      invoked: tasksInvocation.length,
      defaults: defaultTasks.length,
      executables: runnableTasksCount,
      upToDate: upToDateCount);

  String taskPhrase(int count,
          [String singular = 'task', String plural = 'tasks']) =>
      '$count ${count == 1 ? singular : plural}';

  // build log phrases
  final totalTasksPhrase = taskPhrase(totalTasksCount);
  final requestedTasksPhrase = directTasksCount == 0
      ? '${taskPhrase(defaultTasks.length)} (${colorize('default', LogColor.gray)})'
      : '${taskPhrase(directTasksCount)} selected';
  final runnableTasksPhrase =
      style(taskPhrase(runnableTasksCount), LogStyle.bold);
  final dependenciesPhrase = dependenciesCount == 0
      ? ''
      : ', ${taskPhrase(dependenciesCount, 'dependency', 'dependencies')}';
  final upToDatePhrase = upToDateCount > 0
      ? ', $upToDateCount ${colorize('up-to-date', LogColor.green)}'
      : '';

  logger.info('Executing $runnableTasksPhrase out of a total of '
      '$totalTasksPhrase: $requestedTasksPhrase'
      '$dependenciesPhrase$upToDatePhrase');
}
