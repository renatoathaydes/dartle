import 'package:actors/actors.dart';

Function(A) actorAction<A>(Function(A) fun) {
  final actor = Actor.of(fun);
  return (A a) async {
    try {
      return await actor.send(a);
    } finally {
      actor.close();
    }
  };
}
