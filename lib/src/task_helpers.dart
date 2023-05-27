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
Future<void> deleteOutputs(Iterable<Task> tasks) async {
  for (final task in tasks) {
    final outputs = taskOutputs(task);
    if (outputs != null) {
      await deleteAll(outputs);
    }
  }
}
