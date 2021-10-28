## Future release

- forbid tasks from accessing IO resources not declared in inputs/outputs.
- task must run before/after another task without hard dependency.

## 0.11.0

- better error message when no default tasks exist and no tasks are selected.
- new `intersection` method added to `FileCollection`.
- made most `FileCollection` methods more platform-independent (handle path differences better).
- auto-detect dependencies between tasks due to inputs/outputs - error if no explicitly dependency exists. 

## 0.10.0

- ask user whether to create a new Dartle project if executed in directory not containing dartle.dart.
- Dart test task does not bomb when faced with unexpected output.
- fixed #6 - file inputs/outputs are cached separately per task.

## 0.9.1

- updated Dart test model library.

## 0.9.0

- new Dart Test reporter - shows better status of running tests and failed tests at the end.
- improved logging of how many tasks will run or are up-to-date.
- improved show-tasks output: includes which tasks would run and why.
- added `RunConditionCombiner` along with `OR` and `AND` implementations.
- `#3` Dart lib: runPubGet on pubspec.yaml and lock file changes.

## 0.8.0

- non-null-by-default release.
- created dartle_dart library.
- compile dartle.dart into executable automatically when running 'dartle' executable.
- improved log messages.

## 0.6.1

- better 'debug' log level message color.

## 0.6.0

- improved logging output.
- added option to turn off colorful-log.

## 0.5.1

- Fixed Dartle version in published package.

## 0.5.0

- Added CLI --version option.
- Improved help messages.
- Run tasks in parallel when no dependencies force an ordering.
- Use different Isolates to run parallel tasks when their actions is a top-level function and the `-p` flag is used.
- Let tasks take arguments (e.g. `dartle task :arg`).
- Verify task's arguments using its `ArgsValidator`.
- Changed Task action's parameter list to take a non-optional `List<String>`.
- Fixed bug where not all executable tasks were shown with the -s flag.

## 0.4.0

- Implemented task dependencies.
- New option to show all build tasks.
- New option to show task graph.
- Use dart2native to compile dartle build file where available.
- Better error handling to avoid crashes.
- Improved process execution functions.
- Fixed RunOnChanges: must run task if its outputs do not exist.
- Changed failBuild function to throw DartleException (not call exit).

## 0.3.0

- Improved dartle caching.
- Attempt to use fastest snapshot method available to make script runs faster.
- Support choosing tasks by fuzzy name selection.

## 0.2.0

- Implemented dartle executable. Snapshots dartle.dart in order to run faster.

## 0.1.0

- Added basic functionality: run tasks, logging.

## 0.0.0

- Initial version, created by Stagehand
