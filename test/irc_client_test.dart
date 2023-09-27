import 'package:irc_client/irc_client.dart';
import 'package:test/test.dart';

void main() {
  group('A group of tests', () {
    setUp(() {
      // Additional setup goes here.
    });

    test('Parse Test', () {
      final parser = IrcParser();

      parser.parse('test a'.codeUnits);
      parser.parse('bc :ok\n'.codeUnits);

      parser.parse('test a'.codeUnits);
      parser.parse('bc :ok\ntest2'.codeUnits);
      parser.parse('test a'.codeUnits);
      parser.parse('bc d=e:f :ok\n'.codeUnits);

      // expect(awesome.isAwesome, isTrue);
    });
  });
}
