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
