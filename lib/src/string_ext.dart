import 'dart:convert';

import 'package:characters/characters.dart';

extension LineBreakExt on String {
  Stream<List<int>> toByteLines({
    required int maxBytes,
    Converter<String, List<int>> encoder = const Utf8Encoder(),
  }) async* {
    var line = <int>[];
    for (final s in characters) {
      final b = encoder.convert(s);
      if (line.length + b.length <= maxBytes) {
        line.addAll(b);
      } else {
        yield line;
        line = <int>[];
        line.addAll(b);
      }
    }
    yield line;
  }
}
