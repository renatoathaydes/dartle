import 'package:collection/collection.dart' show IterableIntegerExtension;

import '_log.dart';
import 'task.dart';
import 'task_invocation.dart';

/// Hook that will be called when a build is finished because everything is
/// up-to-date.
///
/// Change this value if you prefer to not use the default function which logs
/// the INFO message 'Everything is up-to-date!' in GREEN.
void Function() onEverythingUpToDate = _onEverythingUpToDate;

void _onEverythingUpToDate() {
  logger.info(
    const ColoredLogMessage('Everything is up-to-date!', LogColor.green),
  );
}

void logTasksInfo(Set<Task> tasks, List<ParallelTasks> executableTasks) {
  if (executableTasks.every((pt) => pt.empty)) {
    return;
  }

  final runnableTasksCount = executableTasks.map((t) => t.mustRunCount).sum;

  if (runnableTasksCount == 0) {
    return onEverythingUpToDate();
  }

  final countByReason = {
    for (final reason in InvocationReason.values)
      reason: executableTasks
          .map((t) => t.invocations.where((inv) => inv.reason == reason).length)
          .sum,
  };

  final totalTasksCount = tasks.length;
  final upToDateCount = executableTasks.map((t) => t.upToDateCount).sum;

  // build log phrases
  final totalTasksPhrase = _phrase(totalTasksCount);
  final runnableTasksPhrase = style(_phrase(runnableTasksCount), LogStyle.bold);

  final reasonPhrases = [
    for (final e in countByReason.entries)
      _reportCount(e.value, one: _one(e.key), many: _many(e.key)),
  ].where((e) => e.isNotEmpty);

  final upToDatePhrase = upToDateCount > 0
      ? '$upToDateCount ${colorize('up-to-date', LogColor.green)}'
      : '';

  logger.info(
    'Executing $runnableTasksPhrase out of a total of $totalTasksPhrase: '
    '${reasonPhrases.isEmpty ? '' : reasonPhrases.join(', ')}'
    '${reasonPhrases.isEmpty ? upToDatePhrase : ', $upToDatePhrase'}',
  );
}

String _phrase(int count, [String one = 'task', String many = 'tasks']) =>
    '$count ${count == 1 ? one : many}';

String _reportCount(int count, {required String one, required String many}) =>
    count == 0 ? '' : _phrase(count, one, many);

String _one(InvocationReason reason) => switch (reason) {
  InvocationReason.calledByUser => 'task selected',
  InvocationReason.byDefault => 'task (${colorize('default', LogColor.gray)})',
  InvocationReason.requirement => 'requirement',
  InvocationReason.dependency => 'dependency',
  InvocationReason.synthetic => 'synthetic',
};

String _many(InvocationReason reason) => switch (reason) {
  InvocationReason.calledByUser => 'tasks selected',
  InvocationReason.byDefault => 'tasks (${colorize('default', LogColor.gray)})',
  InvocationReason.requirement => 'requirements',
  InvocationReason.dependency => 'dependencies',
  InvocationReason.synthetic => 'synthetic',
};
