import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// IRC Message
class IrcMessage {
  final String? prefix;
  final String command;
  final String? target;
  final List<String> parameters;

  IrcMessage({
    required this.command,
    this.prefix,
    this.target,
    List<String>? parameters,
  }) : parameters = parameters ?? [];

  void arg(String value) {
    parameters.add(value);
  }

  String? from() {
    if (prefix == null) return null;
    final p = prefix!;

    final i = p.indexOf(RegExp(r'[!@]'));
    if (i < 0) return p;
    return p.substring(0, i);
  }

  @override
  String toString() =>
      '$prefix | $command | $target | ${parameters.join(" | ")}';
}

enum ParseState {
  init,
  prefix,
  target,
  params,
  rest,
}

class IrcParser {
  IrcParser({
    Converter<List<int>, String>? decoder,
  }) : _decoder = decoder ?? Utf8Decoder(allowMalformed: true);

  final Converter<List<int>, String> _decoder;

  Iterable<int>? _rest;
  ParseState _state = ParseState.init;
  int _lastIndex = 0;

  String? _prefix;
  String? _command;
  String? _target;
  List<String> _params = [];

  static final cr = '\r'.codeUnitAt(0);
  static final lf = '\n'.codeUnitAt(0);
  static final space = ' '.codeUnitAt(0);
  static final colon = ':'.codeUnitAt(0);
  static final ban = '!'.codeUnitAt(0);

  String _decodeBytes(Iterable<int> data, int start, int end) =>
      _decoder.convert(data.skip(start).take(end - start).toList());

  Stream<IrcMessage> parse(Iterable<int> data) async* {
    if (_rest != null) {
      data = _rest!.followedBy(data);
    }

    for (final (i, c) in data.indexed) {
      if (c == colon) {
        if (i != _lastIndex) continue;
        switch (_state) {
          case ParseState.init:
            _state = ParseState.prefix;
            _lastIndex = i + 1;
            break;
          case ParseState.target:
            _state = ParseState.rest;
            _lastIndex = i + 1;
            break;
          case ParseState.params:
            _state = ParseState.rest;
            _lastIndex = i + 1;
            break;
          default:
            break;
        }
      } else if (c == space && _state != ParseState.rest) {
        final s = _decodeBytes(data, _lastIndex, i);
        switch (_state) {
          case ParseState.init:
            _command = s;
            _state = ParseState.target;
            break;
          case ParseState.prefix:
            _prefix = s;
            _state = ParseState.init;
            break;
          case ParseState.target:
            _target = s;
            _state = ParseState.params;
            break;
          case ParseState.params:
            _params.add(s);
            break;
          case ParseState.rest:
            break;
        }
        _lastIndex = i + 1;
      } else if (c == cr || c == lf) {
        switch (_state) {
          case ParseState.rest:
            final s = _decodeBytes(data, _lastIndex, i);
            _params.add(s);
            break;
          default:
            break;
        }
        if (_command != null) {
          yield IrcMessage(
            command: _command!,
            prefix: _prefix,
            target: _target,
            parameters: _params,
          );
        }

        _prefix = null;
        _command = null;
        _target = null;
        _params = [];

        _state = ParseState.init;
        _lastIndex = i + 1;
      }
    }
    if (_lastIndex < data.length && 0 < _lastIndex) {
      _rest = data.skip(_lastIndex);
    } else {
      _rest = null;
    }
    _lastIndex = 0;
  }
}

extension IrcMessageExt on RawSocket {
  void sendIrcMessage(
    IrcMessage message, {
    required Converter<String, List<int>> encoder,
  }) {
    final command = encoder.convert(message.command);
    final parameters = message.parameters.map(encoder.convert);

    Iterable<int> data = command;
    if (message.target != null) {
      final target = encoder.convert(message.target!);
      data = data.followedBy([IrcParser.space]).followedBy(target);
    }
    for (final (i, v) in parameters.indexed) {
      if (i + 1 == parameters.length &&
          (v.contains(IrcParser.space) ||
              (v.isNotEmpty && v[0] == IrcParser.colon))) {
        // last parameter contains space.
        data =
            data.followedBy([IrcParser.space, IrcParser.colon]).followedBy(v);
      } else {
        data = data.followedBy([IrcParser.space]).followedBy(v);
      }
    }
    data = data.followedBy([IrcParser.cr, IrcParser.lf]);

    final bytes = data.toList();
    _writeAll(this, bytes);
  }

  static void _writeAll(RawSocket socket, List<int> data) {
    var offset = 0;
    while (0 < data.length - offset) {
      final n = socket.write(data, offset);
      offset += n;
    }
  }
}

class IrcMessageSink implements StreamSink<IrcMessage> {
  final RawSocket socket;
  final Converter<String, List<int>> encoder;

  IrcMessageSink({required this.socket, required this.encoder});

  void introduce(IrcUser user) {
    if (user.pass != null) {
      add(IrcMessage(command: 'PASS')..arg(user.pass!));
    }
    add(IrcMessage(command: 'NICK')..arg(user.nick));
    add(IrcMessage(command: 'USER')
      ..arg(user.user)
      ..arg('0')
      ..arg('*')
      ..arg(user.userRealName ?? user.user));
  }

  void pong(IrcMessage ping) {
    final server = ping.parameters.lastOrNull;
    final response = IrcMessage(
      command: 'PONG',
      parameters: server != null ? [server] : [],
    );
    add(response);
  }

  void handleCtcp(IrcMessage message, {required String nick}) {
    if (message.parameters.length != 1) return;
    if (message.target != nick) return;
    final from = message.from();
    if (from == null) return;

    final ctcpCommand = message.parameters[0];
    if (ctcpCommand == '\x01VERSION\x01') {
      add(IrcMessage(
        command: 'NOTICE',
        target: from,
      )..arg('\x01VERSION ${_versionString()}\x01'));
    } else if (ctcpCommand.startsWith('\x01PING ') &&
        ctcpCommand.endsWith('\x01')) {
      add(
        IrcMessage(
          command: 'NOTICE',
          target: from,
          parameters: message.parameters,
        ),
      );
    } else if (ctcpCommand == '\x01TIME\x01') {
      add(
        IrcMessage(
          command: 'NOTICE',
          target: from,
        )..arg('\x01TIME ${_localDateString()}\x01'),
      );
    }
  }

  String _versionString() => 'irc_client 1.0.0 :Dart/${Platform.version}';

  String _localDateString() {
    final t = DateTime.now();
    final o = t.timeZoneOffset;
    final m = o.inMinutes.abs();
    final hh = (m ~/ 60).toString().padLeft(2, '0');
    final mm = (m % 60).toString().padLeft(2, '0');
    final offs = '${o.isNegative ? "-" : "+"}$hh:$mm';
    return '${t.toIso8601String()}$offs';
  }

  @override
  void add(data) {
    socket.sendIrcMessage(data, encoder: encoder);
  }

  @override
  Future close() {
    return socket.close();
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    // TODO: implement addError
  }

  @override
  Future addStream(Stream<IrcMessage> stream) async {
    await for (final event in stream) {
      add(event);
    }
  }

  @override
  // TODO: implement done
  Future get done => throw UnimplementedError();
}

/// IRC user authorization
class IrcUser {
  final String nick;
  final String user;
  final String? userRealName;
  final String? pass;

  IrcUser({
    required this.nick,
    required this.user,
    this.userRealName,
    this.pass,
  });
}

class _IrcStreamSubscription implements StreamSubscription<IrcMessage> {
  _IrcStreamSubscription(
    this.sink,
    this.cancelOnError,
  );

  final StreamSink<IrcMessage> sink;
  late StreamSubscription<RawSocketEvent> sub;

  void Function(IrcMessage data)? handleData;
  void Function()? handleDone;
  Function? handleError;

  final bool cancelOnError;

  @override
  Future<E> asFuture<E>([E? futureValue]) {
    // TODO: implement asFuture
    throw UnimplementedError();
  }

  @override
  Future<void> cancel() {
    return sub.cancel();
  }

  @override
  bool get isPaused => sub.isPaused;

  @override
  void onData(void Function(IrcMessage data)? handleData) {
    this.handleData = handleData;
  }

  @override
  void onDone(void Function()? handleDone) {
    this.handleDone = handleDone;
  }

  @override
  void onError(Function? handleError) {
    this.handleError = handleError;
  }

  @override
  void pause([Future<void>? resumeSignal]) {
    sub.pause(resumeSignal);
  }

  @override
  void resume() {
    sub.resume();
  }
}

/// IRC connection.
///
/// Receive / Send `IrcMessage`.
class IrcConnection implements Stream<IrcMessage>, StreamSink<IrcMessage> {
  IrcConnection(
    this.client,
    this._encoder,
    this._decoder,
    this._socket,
  );

  final IrcClient client;
  final Converter<String, List<int>> _encoder;
  final Converter<List<int>, String> _decoder;
  final RawSocket _socket;

  late _IrcStreamSubscription _subscription;

  @override
  void add(IrcMessage event) {
    _subscription.sink.add(event);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _subscription.sink.addError(error, stackTrace);
  }

  @override
  Future addStream(Stream<IrcMessage> stream) async {
    await for (final event in stream) {
      add(event);
    }
  }

  @override
  Future<bool> any(bool Function(IrcMessage element) test) {
    // TODO: implement any
    throw UnimplementedError();
  }

  @override
  Stream<IrcMessage> asBroadcastStream(
      {void Function(StreamSubscription<IrcMessage> subscription)? onListen,
      void Function(StreamSubscription<IrcMessage> subscription)? onCancel}) {
    // TODO: implement asBroadcastStream
    throw UnimplementedError();
  }

  @override
  Stream<E> asyncExpand<E>(Stream<E>? Function(IrcMessage event) convert) {
    // TODO: implement asyncExpand
    throw UnimplementedError();
  }

  @override
  Stream<E> asyncMap<E>(FutureOr<E> Function(IrcMessage event) convert) {
    // TODO: implement asyncMap
    throw UnimplementedError();
  }

  @override
  Stream<R> cast<R>() {
    // TODO: implement cast
    throw UnimplementedError();
  }

  @override
  Future close() {
    return _subscription.sink.close();
  }

  @override
  Future<bool> contains(Object? needle) {
    // TODO: implement contains
    throw UnimplementedError();
  }

  @override
  Stream<IrcMessage> distinct(
      [bool Function(IrcMessage previous, IrcMessage next)? equals]) {
    // TODO: implement distinct
    throw UnimplementedError();
  }

  @override
  // TODO: implement done
  Future get done => throw UnimplementedError();

  @override
  Future<E> drain<E>([E? futureValue]) {
    // TODO: implement drain
    throw UnimplementedError();
  }

  @override
  Future<IrcMessage> elementAt(int index) {
    // TODO: implement elementAt
    throw UnimplementedError();
  }

  @override
  Future<bool> every(bool Function(IrcMessage element) test) {
    // TODO: implement every
    throw UnimplementedError();
  }

  @override
  Stream<S> expand<S>(Iterable<S> Function(IrcMessage element) convert) {
    // TODO: implement expand
    throw UnimplementedError();
  }

  @override
  // TODO: implement first
  Future<IrcMessage> get first => throw UnimplementedError();

  @override
  Future<IrcMessage> firstWhere(bool Function(IrcMessage element) test,
      {IrcMessage Function()? orElse}) {
    // TODO: implement firstWhere
    throw UnimplementedError();
  }

  @override
  Future<S> fold<S>(
      S initialValue, S Function(S previous, IrcMessage element) combine) {
    // TODO: implement fold
    throw UnimplementedError();
  }

  @override
  Future<void> forEach(void Function(IrcMessage element) action) {
    // TODO: implement forEach
    throw UnimplementedError();
  }

  @override
  Stream<IrcMessage> handleError(Function onError,
      {bool Function(dynamic error)? test}) {
    // TODO: implement handleError
    throw UnimplementedError();
  }

  @override
  // TODO: implement isBroadcast
  bool get isBroadcast => throw UnimplementedError();

  @override
  // TODO: implement isEmpty
  Future<bool> get isEmpty => throw UnimplementedError();

  @override
  Future<String> join([String separator = ""]) {
    // TODO: implement join
    throw UnimplementedError();
  }

  @override
  // TODO: implement last
  Future<IrcMessage> get last => throw UnimplementedError();

  @override
  Future<IrcMessage> lastWhere(bool Function(IrcMessage element) test,
      {IrcMessage Function()? orElse}) {
    // TODO: implement lastWhere
    throw UnimplementedError();
  }

  @override
  // TODO: implement length
  Future<int> get length => throw UnimplementedError();

  @override
  StreamSubscription<IrcMessage> listen(
    void Function(IrcMessage event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final user = client.user;
    final sink = IrcMessageSink(socket: _socket, encoder: _encoder);
    final parser = IrcParser(decoder: _decoder);
    final sub = _IrcStreamSubscription(sink, cancelOnError ?? false)
      ..onData(onData)
      ..onDone(onDone)
      ..onError(onError);
    sub.sub = _socket.listen(
      (event) {
        switch (event) {
          case RawSocketEvent.read:
            final bytes = _socket.read();
            if (bytes != null) {
              parser.parse(bytes).listen(
                (message) {
                  if (message.command == 'PING') {
                    sink.pong(message);
                  } else if (message.command == 'PRIVMSG') {
                    // Check if is CTCP.
                    sink.handleCtcp(message, nick: user.nick);
                  }

                  final h = sub.handleData;
                  if (h != null) h(message);
                },
                cancelOnError: cancelOnError,
              );
            }
            break;
          case RawSocketEvent.readClosed:
            _socket.close();
            break;
          case RawSocketEvent.closed:
            break;
          case RawSocketEvent.write:
            sink.introduce(user);
            break;
        }
      },
      onDone: () {
        final h = sub.handleDone;
        if (h != null) h();
      },
      onError: (error, stackTrace) {
        final h = sub.handleError;
        if (h != null) h(error, stackTrace);
      },
      cancelOnError: cancelOnError,
    );

    _subscription = sub;
    return sub;
  }

  @override
  Stream<S> map<S>(S Function(IrcMessage event) convert) {
    // TODO: implement map
    throw UnimplementedError();
  }

  @override
  Future pipe(StreamConsumer<IrcMessage> streamConsumer) {
    // TODO: implement pipe
    throw UnimplementedError();
  }

  @override
  Future<IrcMessage> reduce(
      IrcMessage Function(IrcMessage previous, IrcMessage element) combine) {
    // TODO: implement reduce
    throw UnimplementedError();
  }

  @override
  // TODO: implement single
  Future<IrcMessage> get single => throw UnimplementedError();

  @override
  Future<IrcMessage> singleWhere(bool Function(IrcMessage element) test,
      {IrcMessage Function()? orElse}) {
    // TODO: implement singleWhere
    throw UnimplementedError();
  }

  @override
  Stream<IrcMessage> skip(int count) {
    // TODO: implement skip
    throw UnimplementedError();
  }

  @override
  Stream<IrcMessage> skipWhile(bool Function(IrcMessage element) test) {
    // TODO: implement skipWhile
    throw UnimplementedError();
  }

  @override
  Stream<IrcMessage> take(int count) {
    // TODO: implement take
    throw UnimplementedError();
  }

  @override
  Stream<IrcMessage> takeWhile(bool Function(IrcMessage element) test) {
    // TODO: implement takeWhile
    throw UnimplementedError();
  }

  @override
  Stream<IrcMessage> timeout(Duration timeLimit,
      {void Function(EventSink<IrcMessage> sink)? onTimeout}) {
    // TODO: implement timeout
    throw UnimplementedError();
  }

  @override
  Future<List<IrcMessage>> toList() {
    // TODO: implement toList
    throw UnimplementedError();
  }

  @override
  Future<Set<IrcMessage>> toSet() {
    // TODO: implement toSet
    throw UnimplementedError();
  }

  @override
  Stream<S> transform<S>(StreamTransformer<IrcMessage, S> streamTransformer) {
    // TODO: implement transform
    throw UnimplementedError();
  }

  @override
  Stream<IrcMessage> where(bool Function(IrcMessage event) test) {
    // TODO: implement where
    throw UnimplementedError();
  }
}

/// IRC Client
class IrcClient {
  final String host;
  final int port;
  final Duration? timeout;

  final IrcUser user;

  final Converter<String, List<int>> _encoder;
  final Converter<List<int>, String> _decoder;

  /// Create IRC client
  ///
  /// Default encoder is UTF-8.
  ///
  /// Default decoder is UTF-8.
  IrcClient({
    required this.host,
    this.port = 6667,
    required String nick,
    required String user,
    String? userRealName,
    String? pass,
    this.timeout,
    Converter<String, List<int>>? encoder,
    Converter<List<int>, String>? decoder,
  })  : user = IrcUser(
          nick: nick,
          user: user,
          userRealName: userRealName,
          pass: pass,
        ),
        _encoder = encoder ?? Utf8Encoder(),
        _decoder = decoder ?? Utf8Decoder(allowMalformed: true);

  Future<IrcConnection> connect() async {
    final socket = await RawSocket.connect(host, port, timeout: timeout);
    socket.setOption(SocketOption.tcpNoDelay, true);
    return IrcConnection(this, _encoder, _decoder, socket);
  }
}
