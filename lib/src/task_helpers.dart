import 'file_collection.dart';
import 'io_helpers.dart';
import 'run_condition.dart';
import 'task.dart';

/// Get the outputs of a [Task].
///
/// This method can only return the outputs of a Task if its [RunCondition]
/// implements [FilesCondition], otherwise `null` is returned.
FileCollection? taskOutputs(Task task) {
  switch (task.runCondition) {
    case FilesCondition(outputs: var out):
      return out;
    default:
      return null;
  }
}

/// Deletes the outputs of all [tasks].
///
/// This method only works if the task's [RunCondition]s are instances of
/// [FilesCondition].
/// If provided, `exclusions` allows excluding file entities that match by path.
Future<void> deleteOutputs(
  Iterable<Task> tasks, {
  Pattern exclusions = const NeverPattern(),
}) async {
  for (final task in tasks) {
    final outputs = taskOutputs(task);
    if (outputs != null) {
      await deleteAll(outputs - exclusions);
    }
  }
}

/// A [Pattern] that never matches anything.
class NeverPattern implements Pattern {
  const NeverPattern();

  @override
  Iterable<Match> allMatches(String string, [int start = 0]) => const [];

  @override
  Match? matchAsPrefix(String string, [int start = 0]) => null;
}
