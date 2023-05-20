import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:actors/actors.dart';
import 'package:dartle/dartle.dart';
import 'package:test/expect.dart';
import 'package:test/scaffolding.dart';

enum _ServerMessage { start, request, reset }

sealed class _ActorResponse {}

final class _ActorRunning extends _ActorResponse {
  final int port;

  _ActorRunning(this.port);
}

final class _ActorGotRequest extends _ActorResponse {
  final HttpHeaders? headers;

  _ActorGotRequest(this.headers);
}

final class _ServerActor implements Handler<_ServerMessage, _ActorResponse?> {
  Future<HttpServer>? _server;
  HttpHeaders? _latestRequestHeaders;

  Future<HttpServer> init() async {
    final server = await HttpServer.bind('localhost', 0);

    server.listen((req) {
      void send(Object body, [int status = 200]) async {
        req.response
          ..statusCode = status
          ..add(body is String ? utf8.encode(body) : body as List<int>);
        await req.response.flush();
        await req.response.close();
      }

      _latestRequestHeaders = req.headers;
      switch (req.uri.path) {
        case '/json':
          return send(jsonEncode({'json': true}));
        case '/plain':
          return send('Plain text');
        case '/latin1':
          return send(const [203, 216]);
        default:
          return send('Not found', 404);
      }
    });
    return server;
  }

  @override
  FutureOr<_ActorResponse?> handle(_ServerMessage message) async {
    switch (message) {
      case _ServerMessage.start:
        final server = await init();
        return _ActorRunning(server.port);
      case _ServerMessage.request:
        return _ActorGotRequest(_latestRequestHeaders);
      case _ServerMessage.reset:
        _latestRequestHeaders = null;
        return null;
    }
  }

  @override
  FutureOr<void> close() {
    _server?.then((s) => s.close());
  }
}

void main() async {
  // run in Isolate to avoid Dart Test waiting for it
  final serverActor = Actor(_ServerActor());

  final runningResponse = await serverActor.send(_ServerMessage.start);
  final port = (runningResponse as _ActorRunning).port;

  Future<HttpHeaders> waitForReceivedHeaders() async {
    final response = await serverActor.send(_ServerMessage.request);
    return switch (response) {
      _ActorGotRequest(headers: HttpHeaders h) => h,
      _ActorGotRequest(headers: null) => throw 'headers are null',
      _ => throw 'Unexpected response: $response',
    };
  }

  tearDownAll(() => serverActor.close());

  tearDown(() => serverActor.send(_ServerMessage.reset));

  group('download', () {
    test('can download simple text file', () async {
      final text =
          await downloadText(Uri.parse('http://localhost:$port/plain'));
      expect(text, equals('Plain text'));
      final headers = await waitForReceivedHeaders();
      expect(headers['Accept']?.join(','), equals('plain/text'));
    });

    test('can download text file in custom (latin1) encoding', () async {
      final text = await downloadText(
          Uri.parse('http://localhost:$port/latin1'),
          encoding: latin1);
      expect(text, equals('ËØ'));
      final headers = await waitForReceivedHeaders();
      expect(headers['Accept']?.join(','), equals('plain/text'));
    });

    test('fails on 404 by default', () async {
      expect(
          () => downloadText(Uri.parse('http://localhost:$port/wrong')),
          throwsA(isA<HttpCodeException>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having((e) => e.uri.toString(), 'uri',
                  'http://localhost:$port/wrong')));
    });

    test('does not fail on 404 if 404 considered success', () async {
      final text = await downloadText(Uri.parse('http://localhost:$port/wrong'),
          isSuccessfulStatusCode: (code) => code == 404);
      expect(text, equals('Not found'));
    });

    test('can download valid JSON', () async {
      final dynamic json =
          await downloadJson(Uri.parse('http://localhost:$port/json'));
      expect(json['json'], isTrue);
      final headers = await waitForReceivedHeaders();
      expect(headers['Accept']?.join(','), equals('application/json'));
    });
  }, timeout: Timeout(const Duration(seconds: 5)));
}
