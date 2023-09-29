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

TODO: Tell users more about the package: where to find more information, how to
contribute to the package, how to file issues, what response they can expect
from the package authors, and more.
