/// A simple build system written in Dart.
///
/// Tasks are declared in a regular Dart file and can be executed in parallel
/// or in sequence.
///
/// This library provides several Dart utilities useful for automating common
/// tasks, such as copying/moving/transforming files and executing commands,
/// but as build files are just regular Dart, any `dev_dependencies` can be
/// used in build files.
library dartle;

export 'src/_log.dart' show activateLogging, LogColor, ColoredLogMessage;
export 'src/_utils.dart' show elapsedTime;
export 'src/core.dart';
export 'src/dartle_version.g.dart';
export 'src/error.dart';
export 'src/file_collection.dart';
export 'src/helpers.dart';
export 'src/options.dart';
export 'src/run_condition.dart';
export 'src/snapshot.dart';
export 'src/std_stream_consumer.dart';
export 'src/task.dart';
export 'src/task_invocation.dart';
export 'src/task_run.dart';
