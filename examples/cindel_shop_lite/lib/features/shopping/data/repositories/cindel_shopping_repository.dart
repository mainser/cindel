import 'package:cindel_shop_lite/features/shopping/data/datasources/shopping_local_data_source.dart';
import 'package:cindel_shop_lite/features/shopping/domain/entities/shopping_cart.dart';
import 'package:cindel_shop_lite/features/shopping/domain/failures/shopping_failure.dart';
import 'package:cindel_shop_lite/features/shopping/domain/repositories/shopping_repository.dart';

final class CindelShoppingRepository implements ShoppingRepository {
  const CindelShoppingRepository(this._dataSource);

  final ShoppingLocalDataSource _dataSource;

  @override
  Future<void> checkout(List<CartItem> items) async {
    try {
      await _dataSource.checkout(items);
    } catch (error) {
      throw ShoppingStorageFailure.from(error);
    }
  }
}
