class AppException implements Exception {
  final String message;
  final String? code;

  AppException(this.message, {this.code});

  @override
  String toString() => 'AppException: $message${code != null ? ' ($code)' : ''}';
}

class NetworkException extends AppException {
  NetworkException([String message = '网络请求失败']) : super(message);
}

class CacheException extends AppException {
  CacheException([String message = '缓存读取失败']) : super(message);
}

class ParseException extends AppException {
  ParseException([String message = '数据解析失败']) : super(message);
}

class NotFoundException extends AppException {
  NotFoundException([String message = '数据不存在']) : super(message);
}
