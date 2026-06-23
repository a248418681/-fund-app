import 'package:dio/dio.dart';

/// 所有数据源 mixin 通过此接口访问 Dio 实例
/// 宿主类实现 [dio] getter 即可
abstract class RemoteDioAccessor {
  Dio get dio;
}
