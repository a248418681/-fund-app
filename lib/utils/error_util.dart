import 'package:dio/dio.dart';

class ErrorUtil {
  static String format(Object? e) {
    if (e is DioException) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return '请求超时，请检查网络';
        case DioExceptionType.connectionError:
          return '网络连接失败，请稍后重试';
        case DioExceptionType.cancel:
          return '';
        case DioExceptionType.badResponse:
          final code = e.response?.statusCode ?? 0;
          if (code >= 500) return '服务器繁忙，请稍后重试';
          if (code == 404) return '接口不存在(404)';
          return '请求失败($code)';
        default:
          return '网络异常，请稍后重试';
      }
    }
    if (e is FormatException) return '数据解析失败';
    final msg = e?.toString() ?? '未知错误';
    if (msg.length > 100) return '数据加载失败';
    return msg;
  }
}
