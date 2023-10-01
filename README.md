A trivial IRC client library.

## Features

Supports:

- Connect to IRC server with plain text or secured with TLS.
- TLS with client certificate authentication. (for irc.oftc.net)
- SASL authentication. (for irc.libera.chat)
- Automatic PING response.
- Basic CTCP response. (CTCP VERSION / PING / TIME)

## Usage

```dart
final client = IrcClient();
final connection = await client.connect();
await for (final msg in connection) {
  print(msg);
}
```

## Additional information

This library is in its very early stages.
It only supports sending and receiving raw IRC messages.
No useful methods are available yet.
