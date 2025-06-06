# Dartle Release Notes

## done, waiting for next release

# 0.33.0

### Dartle Cache

- when directory is deleted, report all files within it that were deleted, not just the directory itself.

# 0.32.0

### Dartle Cache

- made `FileChange` sendable through Isolates (some instances of `FileSystemEntity` may not be, so internally `FileChange` no longer holds one).
- added `FileChange.path` and `FileChange.entityKind` properties.

# 0.31.0

### Dartle Cache

- proper support for caching absolute paths. Makes the cache movable. 

# 0.30.0

### Dartle Core

- log reason why a task will run.

### Dartle Cache

- improved cache internal structure (cache format version changed to `0.3`).
  Better debugging by keeping file names closer to original names.

# 0.29.0

### Dartle Core

- no longer change `Directory.current` in Actor tasks. Use `isolate_current_directory` package instead.

### Dartle Dart

- added `sources`, `buildSources` and `testSources` properties to `DartConfig`.
- improved definition of default tasks inputs. Fixes bug where tasks ran without need.

# 0.28.1

### Dartle Core

- fixed regression: `format` task hangs if no argument is provided.

# 0.28.0

### Dartle Core

- `runBasic` function now returns the tasks that may have been executed.
- Fixed exports: both `ChangeSet` and `FileChange` from `dartle_cache` are re-exported now.

### Dartle Cache

- Moved `ChangeSet` to `dartle_cache` library. It's still exported by the main library as well.

### Dartle Dart

- `format` task is now incremental (only changed files are reformatted).

# 0.27.0

- log task name in bold.
- bumped all libraries versions.

# 0.26.0

- bumped all libraries versions.

# 0.25.0

### Dartle Core

- removed `cache` option to `createCleanTask` function and `RunToDelete` class.
- fixed handling of `FINER` log messages to match `TRACE` log level.
- fixed bug in `RunToDelete`: do not remove full directory as it may contain files filtered out by file-collection.
- big internal reorganization of Dart files. Should not affect users importing `packge:dartle/dartle.dart`.

### Dartle Cache

- changed methods that took `TaskInvocation` to use `name` and `args`. Avoids taking up dependencies on Dartle Core
  types.

# 0.24.0

### Dartle Core

- fixed regression (in 0.23.1) reporting task errors.
- changed signature of `execProc` and `execRead` to take a function instead of `Set<int>`
  to determine when exit code is success.
- changed signature of `download` and related functions to take a function instead of `Set<int>`
  to determine when status code is success.
- added optional `SecurityContext` argument to `download` functions.

# 0.23.2

### Dartle Core

- fixed mistake in newly created project.

# 0.23.1

### Dartle Core

- removed double warning on missing task invocation.
- report single Exception without wrapping it into MultipleExceptions.
- fixed creation of new project if dartle.dart or pubspec.yaml files are missing.

# 0.23.0

### Dartle Core

- require Dart 3.
- removed Freezed build dependency.
- added `--disable-cache`, `-d` command-line option.
- added helper functions: `taskOutputs`, `tar`, `untar`, `tempFile`, `tempDir`.
- added parameter `FileCollection`: `allowAbsolutePaths` (not recommended to set to `true` in normal builds).
- improved reporting of how many tasks will run/dependencies/defaults.

### Dartle Cache

- new method: `hasTask` to determine whether a task has been executed.

# 0.22.2

- fixed metadata for Dart 3.

# 0.22.1

### DartleCache

- fixed mistake that caused build tasks' cached artifacts to be deleted accidentally.

# 0.22.0

### Dartle Core

- added new helper functions: `download`, `downloadText` and `downloadJson`.
- added helper function `homeDir`.
- added extension function to `File`: `writeBinary`.
- added default name `clean` for task created by `createCleanTask`.
- stopped exporting `StdStreamConsumer`. Use `execRead`, `execProc` or `exec` functions configuration instead.
- made `execProc` fail with `ProcessExitCodeException` if the process exit code is not zero (configurable via
  parameter `successCodes`).
- `failBuild` now returns `Never`, given it always throws `DartleException`.

# 0.21.0

### Dartle Cache

- fixed handling of relative paths (in tasks, keys, file paths) in the cache.

# 0.20.0

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
- improved `DartleCache` so it will not trust timestamps when diff is less than 1 second. Some file systems have low
  resolution timestamps.
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
