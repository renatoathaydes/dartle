final _capitalLetterPattern = RegExp(r'[A-Z]');

String decapitalize(String text) {
  if (text.startsWith(_capitalLetterPattern)) {
    return text.substring(0, 1).toLowerCase() + text.substring(1);
  }
  return text;
}

/// Splits the words in the given text using camel-case word separation.
///
/// Example: helloWorld become [hello, world].
List<String> splitWords(String text) {
  var idx = text.indexOf(_capitalLetterPattern, text.isEmpty ? 0 : 1);
  if (idx < 0) return [text];
  final result = <String>[decapitalize(text.substring(0, idx))];
  while (idx >= 0 && idx < text.length) {
    var nextIdx = text.indexOf(_capitalLetterPattern, idx + 1);
    if (nextIdx < 0) nextIdx = text.length;
    result.add(decapitalize(text.substring(idx, nextIdx)));
    idx = nextIdx;
  }
  return result;
}

String? findMatchingByWords(String searchText, List<String> options) {
  if (searchText.isEmpty) return null;
  var result = options.firstWhere((opt) => opt == searchText, orElse: () => '');
  // if there's an exact match, return it
  if (result.isNotEmpty) return result;

  // no exact match found, try to find match by words after splitting the text
  final searchTerms = splitWords(searchText);
  optionsLoop:
  for (final option in options) {
    final optionWords = splitWords(option);
    if (optionWords.length < searchTerms.length) continue; // cannot match
    for (var i = 0; i < searchTerms.length; i++) {
      if (!optionWords[i].startsWith(searchTerms[i])) {
        continue optionsLoop;
      }
    }
    // if we get here, we have a match!
    if (result.isEmpty) {
      // only match so far
      result = option;
    } else {
      // but there was already a match, so the search term is ambiguous!
      return null;
    }
  }
  return result.isEmpty ? null : result;
}

/// Calls [elapsedTimeIn] with the value of `stopwatch.elapsed`.
String elapsedTime(Stopwatch stopwatch) => elapsedTimeIn(stopwatch.elapsed);

/// Formats the given duration using spaced verbal units with a `,` between
/// each unit.
///
/// For example, `23h, 32m, 45s`, `1s, 250ms`, `10ms, 850μs`.
///
/// Units:
///
/// - `d` for days
/// - `h` for hours
/// - `m` for minutes
/// - `s` for seconds
/// - `ms` for milliseconds
/// - `μs` for microseconds
///
/// Durations longer than *one minute* do not display `ms` and `μs`.
/// Durations longer than *one second* do not display `μs`.
String elapsedTimeIn(Duration d) {
  final builder = StringBuffer();
  final (days, hours, mins, secs, millis, micros) = (
    d.inDays,
    d.inHours % 24,
    d.inMinutes % 60,
    d.inSeconds % 60,
    d.inMilliseconds % 1_000,
    d.inMicroseconds % 1_000,
  );

  void append(String unit, num value) {
    if (builder.isNotEmpty) builder.write(', ');
    builder.write(value);
    builder.write(unit);
  }

  if (days > 0) append('d', days);
  if (0 < hours && hours < 24) append('h', hours);
  if (0 < mins && mins < 60) append('m', mins);
  if (0 < secs && secs < 60) append('s', secs);
  if (days > 0 || hours > 0 || mins > 0) return builder.toString();
  if (0 < millis && millis < 1_000) append('ms', millis);
  if (secs > 0) return builder.toString();
  if (0 < micros && micros < 1_000) append('μs', micros);

  if (builder.isEmpty) return '0μs';

  return builder.toString();
}
