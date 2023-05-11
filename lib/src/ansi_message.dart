import 'package:io/ansi.dart' as ansi;

import 'message.dart';

final _reset = [ansi.resetAll.escape];

/// A log message that may be displayed with ANSI modifiers
/// (i.e. fore/background colors and styles).
class AnsiMessage with Message {
  final List<AnsiMessagePart> parts;

  const AnsiMessage(this.parts);

  @override
  Object getPrintable(bool useColor) {
    if (useColor) {
      List<String> end = _endsWithReset() ? const [] : _reset;
      return parts
          .map((e) => e.when(code: (c) => c.escape, text: (t) => t.toString()))
          .followedBy(end)
          .join('');
    }
    return parts
        .map((e) => e.when(code: (c) => null, text: (t) => t.toString()))
        .where((e) => e != null)
        .join('');
  }

  bool _endsWithReset() {
    final index = parts.lastIndexWhere((part) => part is CodeAnsiMessagePart);
    if (index < 0) return true; // as there's no code
    return parts[index] == const AnsiMessagePart.code(ansi.resetAll);
  }
}

sealed class AnsiMessagePart {
  const factory AnsiMessagePart.code(ansi.AnsiCode code) = CodeAnsiMessagePart;

  const factory AnsiMessagePart.text(String text) = TextAnsiMessagePart;

  T when<T>(
      {required T Function(ansi.AnsiCode) code,
      required T Function(String) text});
}

class CodeAnsiMessagePart implements AnsiMessagePart {
  final ansi.AnsiCode code;

  const CodeAnsiMessagePart(this.code);

  @override
  T when<T>(
      {required T Function(ansi.AnsiCode p1) code,
      required T Function(String p1) text}) {
    return code(this.code);
  }

  @override
  String toString() {
    return 'CodeAnsiMessagePart{code: $code}';
  }
}

class TextAnsiMessagePart implements AnsiMessagePart {
  final String text;

  const TextAnsiMessagePart(this.text);

  @override
  T when<T>(
      {required T Function(ansi.AnsiCode p1) code,
      required T Function(String p1) text}) {
    return text(this.text);
  }

  @override
  String toString() {
    return 'TextAnsiMessagePart{text: $text}';
  }
}
