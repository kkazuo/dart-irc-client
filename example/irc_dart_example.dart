// ignore_for_file: avoid_print

import 'dart:math';

import 'package:irc_dart/irc_dart.dart';

void main() async {
  final client = IrcClient(
    // host: 'irc.rizon.net',
    host: 'irc.libera.chat',
    port: 6697,
    secure: true,
    nick: 'n${Random().nextInt(100000000).toString().padLeft(8, '0')}',
    user: 'dart@example.com',
  );

  final connection = await client.connect();
  print('get conn');
  await for (final msg in connection) {
    print(msg);

    if (msg.command == 'PRIVMSG' && msg.parameters.isNotEmpty) {
      if (msg.parameters[0].startsWith('hi')) {
        connection.add(
          IrcMessage(
            command: 'NOTICE',
            target: (msg.target?.startsWith('#') ?? false)
                ? msg.target
                : msg.from(),
          )..arg('Hi ${msg.from()}!'),
        );

        await connection.msg(to: '#irc_dart', 'Hello, world!');
      } else if (msg.parameters[0].startsWith('q')) {
        connection.add(IrcMessage(command: 'QUIT')..arg('Bye'));
      }
    } else if (msg.command == '001') {
      connection.add(IrcMessage(command: 'JOIN')..arg('#irc_dart'));
    }
  }
  print('@ END @');
}
