import 'dart:io';
import 'dart:isolate';

import 'package:actors/actors.dart';
import 'package:structured_async/structured_async.dart';

import '_log.dart';

Future Function(A) actorAction<A>(Function(A) fun) {
  final actor = Actor.of(_initializedActorFun(fun));
  return (A a) => CancellableFuture.ctx((ctx) async {
        ctx.scheduleOnCompletion(actor.close);
        ctx.scheduleOnCancel(actor.close);
        try {
          return await actor.send(a);
        } on MessengerStreamBroken {
          // actor closed, we got cancelled
          throw const FutureCancelled();
        }
      });
}

Function(A) _initializedActorFun<A>(Function(A) fun) {
  final workingDir = Directory.current.path;
  final logLevel = logger.level;
  final logName = logger.name;
  final colorful = colorfulLog;
  return (a) {
    // activate logging in the new Isolate!
    activateLogging(logLevel,
        colorfulLog: colorful,
        logName: '$logName-${Isolate.current.debugName ?? '?'}');

    // make sure the working directory is the same as in the original env...
    // this makes the isolate_current_directory package, in particular, work!
    Directory.current = workingDir;
    return fun(a);
  };
}
