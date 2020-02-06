## Future release

- forbid tasks from accessing IO resources not declared in inputs/outputs.

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
