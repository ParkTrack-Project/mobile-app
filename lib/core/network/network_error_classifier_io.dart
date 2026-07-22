import 'dart:io';

bool isSocketNetworkError(Object error) =>
    error is SocketException ||
    error is HandshakeException ||
    error is HttpException;
