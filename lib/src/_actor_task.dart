import 'package:actors/actors.dart';
import 'package:structured_async/structured_async.dart';

Future Function(A) actorAction<A>(Function(A) fun) {
  final actor = Actor.of(fun);
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
