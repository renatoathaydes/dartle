import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:io/ansi.dart' as ansi;

import 'message.dart';

part 'ansi_message.freezed.dart';

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
    final index = parts.lastIndexWhere((part) => part is Code);
    if (index < 0) return true; // as there's no code
    return parts[index] == const AnsiMessagePart.code(ansi.resetAll);
  }
}

@freezed
class AnsiMessagePart with _$AnsiMessagePart {
  const factory AnsiMessagePart.code(ansi.AnsiCode code) = Code;

  const factory AnsiMessagePart.text(String text) = Text;
}
