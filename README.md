A trivial IRC client library.

## Features

Supports:

- Connect to IRC server with plain text or secured with TLS.
- SASL authentication.
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
