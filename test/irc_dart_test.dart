import 'package:irc_dart/irc_dart.dart';
import 'package:test/test.dart';

void main() {
  group('A group of tests', () {
    setUp(() {
      // Additional setup goes here.
    });

    test('Parse Test', () async {
      final parser = IrcParser();

      parser.parse('test a'.codeUnits);
      parser.parse('bc :ok\n'.codeUnits);

      parser.parse('test a'.codeUnits);
      parser.parse('bc :ok\ntest2'.codeUnits);
      parser.parse('test a'.codeUnits);
      parser.parse('bc d=e:f :ok\n'.codeUnits);

      await for (final m in parser.parse('AUTHENTICATE +\n'.codeUnits)) {
        expect(m, IrcMessage(command: 'AUTHENTICATE', target: '+'));
      }

      // expect(awesome.isAwesome, isTrue);
    });

    test('Line Breaker', () async {
      const text = 'hello 世界!';

      final ls = await text.toByteLines(maxBytes: 4).toList();
      expect(ls.length, 4);
      expect(ls[0], [104, 101, 108, 108]);
      expect(ls[1], [111, 32]);
      expect(ls[2], [228, 184, 150]);
      expect(ls[3], [231, 149, 140, 33]);
    });
  });
}
