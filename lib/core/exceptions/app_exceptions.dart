class AppException implements Exception {
  final String message;
  final String? code;

  AppException(this.message, {this.code});

  @override
  String toString() =>
      'AppException: $message${code != null ? ' ($code)' : ''}';
}

class NetworkException extends AppException {
  NetworkException([super.message = '网络请求失败']);
}

class CacheException extends AppException {
  CacheException([super.message = '缓存读取失败']);
}

class ParseException extends AppException {
  ParseException([super.message = '数据解析失败']);
}

class NotFoundException extends AppException {
  NotFoundException([super.message = '数据不存在']);
}
