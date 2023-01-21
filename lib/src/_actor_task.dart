import 'dart:io';
import 'dart:isolate';

import 'package:actors/actors.dart';
import 'package:structured_async/structured_async.dart';

import '_log.dart';
import 'task_run.dart' show IncrementalAction, ChangeSet;

/// An Action that may or may not be an [IncrementalAction].
///
/// If [changes] are `null`, then the action is non-incremental.
typedef MaybeIncrementalAction = Function(
    List<String> args, ChangeSet? changes);

class _ActorMessage {
  final List<String> args;
  final ChangeSet? changes;

  _ActorMessage(this.args, this.changes);
}

MaybeIncrementalAction actorAction(Function(List<String>) fun) {
  final actor = Actor.of(_initializedActorFun(fun));
  return (args, changes) => CancellableFuture.ctx((ctx) async {
        ctx.scheduleOnCompletion(actor.close);
        ctx.scheduleOnCancel(actor.close);
        try {
          return await actor.send(_ActorMessage(args, changes));
        } on MessengerStreamBroken {
          // actor closed, we got cancelled
          throw const FutureCancelled();
        }
      });
}

Function(_ActorMessage) _initializedActorFun<A>(Function(List<String>) fun) {
  final workingDir = Directory.current.path;
  final logLevel = logger.level;
  final logName = logger.name;
  final colorful = colorfulLog;
  return (message) {
    // activate logging in the new Isolate!
    activateLogging(logLevel,
        colorfulLog: colorful,
        logName: '$logName-${Isolate.current.debugName ?? '?'}');

    // make sure the working directory is the same as in the original env...
    // this makes the isolate_current_directory package, in particular, work!
    Directory.current = workingDir;

    return runAction(fun, message.args, message.changes);
  };
}

Future<void> runAction(Function(List<String>) action, List<String> args,
    ChangeSet? changes) async {
  if (changes == null) {
    return action(args);
  }
  return (action as IncrementalAction)(args, changes);
}
