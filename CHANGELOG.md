## Future release

- forbid tasks from accessing IO resources not declared in inputs/outputs.

## done, waiting for next release

### Dartle Core

- fixed bug in `deleteAll` in which it deleted full directory, not respecting `fileExtensions` or `exclusions` filters.
- added `trace` log level, used it for logging cache file checks.
- added optional `cache` parameter to `createCleanTask`.

# 0.19.0

### Dartle Core

- support for incremental task actions.
- include task ArgsValidator info on verbose usage.
- removed dependency on `file` package.
- force deletion of task outputs when required.
- better error reporting on conflicting file collections for task RunCondition.

### Dartle Cache

- introduced versioning for cache. Allows future evolution.
- better detection of directory changes when files are deleted.

### Dartle Dart

- made the `test` task incremental. Only changed tests are executed. Use `-f` to force all.

# 0.18.0

### Dartle Core

- automatically run `dart pub get` before trying to compile `dartle.dart` if dependencies not downloaded yet.
- do not re-run task if previous run did not create certain declared outputs.
- added better support for logging colored/styled messages without formatting.
- logged messages are now printed in the same `Zone` they were emitted from.

## 0.17.0

### Dartle Core

- log stack-traces of all Exceptions when error is unknown or logging level is `debug`.
- fixed logger initialization on new task Actors. Parallel task action logging should now work properly.
- invalidate Dartle cache when re-compiling dartle.dart as tasks may have been modified.

## 0.16.0

### Dartle Core

- improved new projects created when 'dartle.dart' file is not found.
- only log task's runCondition when `debug` logging is enabled.
- log executable tasks in a more compact way to better support large number of tasks.

## 0.15.0

### Dartle Core

- expose `runBasic` function to allow embedding Dartle in other CLI tools.
- made it possible to create `DartleCache` on a non-default location.
- added support for _exclusions_ in `FileCollection` for directories.
- added `union` method to `FileCollection`.
- added `MultiFileCollection` type.
- added `createCleanTask` function to make it easier to clean builds.
- changed CLI option `--colorful-log` to `--color`.
- respect `NO_COLOR` environment variable (https://no-color.org/).
- added `environment` argument to `runDartExe` function.
- removed restriction on tasks ins/outs having to be within the project root dir.
- display tasks' runCondition when displaying task information (-s option).

### Dartle Dart

- fixed tasks inputs/outputs to respect `DartleDart.rootDir`.
- added new task, `compileExe` to compile executables declared in pubspec.

## 0.14.1

- fixed the version in distribution.

## 0.14.0

### Dartle Core

- breaking change: refactored FileCollection (incl. `file`, `dir` functions). Simplified how collections may be defined.
- added 'PROFILE' log level and logged times of each significant build step.
- cleanup cache entries that are no long relevant after build.
- run post-run actions at end of each TaskPhase instead of only at the end of the build.
- better reporting of which tasks failed at end of build.
- cancel all pending tasks immediately on first build failure.
- `deleteOutputs` function now works with all instances of `FileCondition`, not only `RunOnChanges`.
- new `RunCondition` implementation: `RunToDelete` (used to implement _cleaning_ tasks).
- fixed `deleteAll` so it removes directories after emptying them.
- improved `DartleCache` so it will not trust timestamps when diff is less than 1 second. Some file systems have low resolution timestamps.
- `DartleCache` now hashes files by loading small buffer into memory at a time instead of whole file.
- `DartleCache` hash now distinguishes between empty file and empty directory.

> Note: the file collection change was necessary for Dartle to be able to reliably detect
> build misconfiguration. It was previously next to impossible to determine when tasks had
> clashing outputs or were missing dependencies given the order in which files are read and
> written to. The new API is less powerful but should suffice in most cases, and it allows
> computing the intersection between tasks inputs and outputs reliably... that lets Dartle
> provide much more powerful diagnostics, getting it closer to providing reproduce-able builds. 

### Dartle Dart

- breaking change: replaced `DartConfig.runBuildRunner` with `DartConfig.buildRunnerRunCondition`.
- improved Dart tasks dependencies to avoid errors in edge cases.

> Note: the new `DartConfig.buildRunnerRunCondition` property allows better control over when
> the `runBuildRunner` task runs, which is important as it's an expensive task.

## 0.12.1

- include custom task phases in information about tasks.

## 0.12.0

- added build phases to ensure ordering between tasks without dependencies: `setup`, `build`, `teardown`.
- enabled parallelization of tasks by default.

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
