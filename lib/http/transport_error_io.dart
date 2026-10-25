import 'package:http2/http2.dart';

bool isTransportConnectionError(Object? error) =>
    error is TransportConnectionException;
