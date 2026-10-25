class _NoopService {
  dynamic noSuchMethod(Invocation invocation) => null;
}

final dynamic videoPlayerServiceHandler = _NoopService();
final dynamic audioSessionHandler = _NoopService();

Future<void> setupServiceLocator() async {}
