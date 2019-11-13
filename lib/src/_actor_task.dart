import 'package:actors/actors.dart';

Function(A) actorAction<A>(Function(A) fun) {
  final actor = Actor.of(fun);
  return actor.send;
}
