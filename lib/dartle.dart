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

export 'src/core.dart';
export 'src/error.dart';
export 'src/helpers.dart';
export 'src/task.dart';
