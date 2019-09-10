/// A library exposing the mechanism used by dartle to cache resources and
/// intelligently determine which tasks must run, and which tasks may be
/// skipped.
///
/// This allows user code to decide, for example, when to re-run jobs which
/// depend on certain inputs, and have known outputs, as in such cases the
/// outputs do not need to be re-computed as long as they have not changed
/// since last time they were built from the same inputs.
library dartle_cache;

export 'src/cache.dart';
export 'src/core.dart' show configure;
export 'src/error.dart';
export 'src/io.dart';
