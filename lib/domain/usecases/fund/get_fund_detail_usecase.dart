import '../../entities/fund_entity.dart';
import '../../repositories/fund_repository.dart';
import '../../../core/exceptions/app_exceptions.dart';

class FundDataException extends AppException {
  FundDataException(String code) : super('获取基金详情失败: $code', code: code);
}

class GetFundDetailUseCase {
  final FundRepository _repository;

  GetFundDetailUseCase(this._repository);

  Future<FundAccurateData> call(String code) async {
    try {
      return await _repository.fetchFundAccurateData(code);
    } on AppException {
      rethrow;
    } catch (e) {
      throw FundDataException(code);
    }
  }
}
