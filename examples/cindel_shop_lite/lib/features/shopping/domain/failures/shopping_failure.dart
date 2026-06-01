final class ShoppingStorageFailure implements Exception {
  const ShoppingStorageFailure(this.message, [this.cause]);

  factory ShoppingStorageFailure.from(Object error) {
    if (error is ShoppingStorageFailure) {
      return error;
    }
    if (error is ShoppingStockFailure) {
      return ShoppingStorageFailure(error.message, error);
    }
    return ShoppingStorageFailure('Checkout operation failed.', error);
  }

  final String message;
  final Object? cause;

  @override
  String toString() => '$message ${cause ?? ''}'.trim();
}

final class ShoppingStockFailure implements Exception {
  const ShoppingStockFailure({
    required this.productName,
    required this.requested,
    required this.available,
  });

  final String productName;
  final int requested;
  final int available;

  String get message {
    if (available == 0) {
      return '$productName is out of stock.';
    }
    return '$productName only has $available available.';
  }

  @override
  String toString() => message;
}
