import 'dart:async';

import 'package:cindel/cindel.dart';

import '../database/database_directory.dart';
import '../models/realworld_models.dart';
import 'scenario_report.dart';

final class CindelRealworldRunner {
  const CindelRealworldRunner._();

  static Future<CindelRealworldReport> runAll() async {
    final steps = <String>[];
    final directory = await cindelRealworldDatabaseDirectory();
    steps.add('directory');

    var database = await Cindel.open(
      directory: directory,
      schemas: cindelRealworldSchemas,
    );
    steps.add('open');

    try {
      final state = await _seedOperationalData(database);
      steps.add('seed');

      await _runCrudAndQueries(database, state);
      steps.add('crud_queries');

      await _runLinksAndBacklinks(database, state);
      steps.add('links');

      await _runWatchers(database, state);
      steps.add('watchers');

      await database.close();
      steps.add('close');

      database = await Cindel.open(
        directory: directory,
        schemas: cindelRealworldSchemas,
      );
      steps.add('reopen');

      await _verifyPersistence(database, state);
      steps.add('persistence');

      await _cleanup(database, state);
      steps.add('cleanup');

      return CindelRealworldReport(
        databaseDirectory: directory,
        steps: List.unmodifiable(steps),
      );
    } finally {
      await database.close();
    }
  }
}

final class _ScenarioState {
  const _ScenarioState({
    required this.primaryCategoryId,
    required this.secondaryCategoryId,
    required this.customerId,
    required this.productId,
    required this.secondaryProductId,
    required this.paymentId,
    required this.orderId,
    required this.inventoryMovementIds,
  });

  final int primaryCategoryId;
  final int secondaryCategoryId;
  final int customerId;
  final int productId;
  final int secondaryProductId;
  final int paymentId;
  final int orderId;
  final List<int> inventoryMovementIds;
}

Future<_ScenarioState> _seedOperationalData(CindelDatabase database) async {
  final now = DateTime.utc(2026, 1, 15, 12);
  final electronics = Category()
    ..slug = 'electronics'
    ..name = 'Electronics'
    ..sortOrder = 1;
  final groceries = Category()
    ..slug = 'groceries'
    ..name = 'Groceries'
    ..sortOrder = 2;
  final customer = Customer()
    ..email = 'ana@example.com'
    ..name = 'Ana Martinez'
    ..active = true
    ..loyaltyPoints = 42
    ..lifetimeValue = 1200.50
    ..signedUpAt = now.subtract(const Duration(days: 300))
    ..preferredResponseTime = const Duration(hours: 4)
    ..status = CustomerStatus.active
    ..tier = CustomerTier.gold
    ..tags = const ['vip', 'newsletter']
    ..defaultShippingAddress = _customerAddress(
      'Main St 1',
      'Boston',
      'US',
      02110,
    )
    ..savedAddresses = [
      _customerAddress('Main St 1', 'Boston', 'US', 02110),
      _customerAddress('Warehouse Ave 8', 'Austin', 'US', 78701),
    ];
  final keyboard = Product()
    ..sku = 'SKU-KEYBOARD'
    ..name = 'Mechanical Keyboard'
    ..description = 'Compact mechanical keyboard for daily work'
    ..price = 129.99
    ..stock = 8
    ..active = true
    ..createdAt = now.subtract(const Duration(days: 10))
    ..tags = const ['hardware', 'keyboard']
    ..details = (ProductDetails()
      ..manufacturer = 'Cindel Hardware'
      ..weight = 0.8
      ..materials = const ['aluminum', 'pbt']
      ..warranty = (Warranty()
        ..months = 24
        ..provider = 'Cindel Care'));
  final coffee = Product()
    ..sku = 'SKU-COFFEE'
    ..name = 'Coffee Beans'
    ..description = 'Medium roast beans for office kitchens'
    ..price = 18.75
    ..stock = 64
    ..active = true
    ..createdAt = now.subtract(const Duration(days: 2))
    ..tags = const ['kitchen', 'consumable']
    ..details = (ProductDetails()
      ..manufacturer = 'Cindel Pantry'
      ..weight = 1
      ..materials = const ['arabica']
      ..warranty = (Warranty()
        ..months = 1
        ..provider = 'Pantry Support'));
  final payment = Payment()
    ..transactionId = 'PAY-1001'
    ..method = PaymentMethod.card
    ..status = PaymentStatus.authorized
    ..amount = 259.98
    ..authorizedAt = now;
  final order = CustomerOrder()
    ..orderNumber = 'ORD-1001'
    ..status = OrderStatus.submitted
    ..createdAt = now
    ..total = 259.98
    ..priority = true
    ..shippingAddress = _orderAddress('Main St 1', 'Boston', 'US', 02110)
    ..items = [
      OrderItem()
        ..sku = 'SKU-KEYBOARD'
        ..productName = 'Mechanical Keyboard'
        ..quantity = 2
        ..unitPrice = 129.99
        ..appliedCoupons = const ['LAUNCH10'],
    ]
    ..note = 'Ship after payment capture.';
  final saleMovement = InventoryMovement()
    ..reference = 'INV-SALE-1001'
    ..createdAt = now
    ..quantity = -2
    ..type = MovementType.sale
    ..reason = 'Order ORD-1001';
  final adjustmentMovement = InventoryMovement()
    ..reference = 'INV-ADJUST-1001'
    ..createdAt = now.add(const Duration(minutes: 1))
    ..quantity = 1
    ..type = MovementType.adjustment
    ..reason = 'Cycle count';
  final settings = AppSetting()
    ..key = 'checkout.enabled'
    ..value = 'true'
    ..enabled = true
    ..updatedAt = now;

  await database.writeTxn<void>(() async {
    await database.categories.putAll([electronics, groceries]);
    await database.customers.put(customer);
    await database.products.putAll([keyboard, coffee]);
    await database.payments.put(payment);
    await database.orders.put(order);
    await database.inventoryMovements.putAll([
      saleMovement,
      adjustmentMovement,
    ]);
    await database.appSettings.put(settings);

    keyboard.category.value = electronics;
    coffee.category.value = groceries;
    order.customer.value = customer;
    order.payment.value = payment;
    saleMovement.product.value = keyboard;
    adjustmentMovement.product.value = keyboard;

    await keyboard.category.save();
    await coffee.category.save();
    await order.customer.save();
    await order.payment.save();
    await saleMovement.product.save();
    await adjustmentMovement.product.save();
  });

  _expectTrue(customer.dbId > 0, 'customer id should be allocated');
  _expectTrue(keyboard.dbId > 0, 'product id should be allocated');
  _expectTrue(order.dbId > 0, 'order id should be allocated');

  return _ScenarioState(
    primaryCategoryId: electronics.dbId,
    secondaryCategoryId: groceries.dbId,
    customerId: customer.dbId,
    productId: keyboard.dbId,
    secondaryProductId: coffee.dbId,
    paymentId: payment.dbId,
    orderId: order.dbId,
    inventoryMovementIds: [saleMovement.dbId, adjustmentMovement.dbId],
  );
}

Future<void> _runCrudAndQueries(
  CindelDatabase database,
  _ScenarioState state,
) async {
  final customer = await database.customers.get(state.customerId);
  _expect(customer?.email, 'ana@example.com', 'customer should read by id');
  _expect(
    customer?.defaultShippingAddress?.city,
    'Boston',
    'embed should read',
  );
  _expect(
    customer?.savedAddresses.length,
    2,
    'embedded object list should read',
  );

  final replacement = Customer()
    ..email = 'ANA@example.com'
    ..name = 'Ana M.'
    ..active = true
    ..loyaltyPoints = 55
    ..lifetimeValue = 1300.50
    ..signedUpAt = customer!.signedUpAt
    ..preferredResponseTime = customer.preferredResponseTime
    ..status = CustomerStatus.active
    ..tier = CustomerTier.gold
    ..tags = const ['vip', 'renewed']
    ..defaultShippingAddress = customer.defaultShippingAddress
    ..savedAddresses = customer.savedAddresses;
  await database.customers.putByEmail(replacement);
  _expect(
    replacement.dbId,
    state.customerId,
    'unique replace helper should reuse customer id',
  );

  final product = await database.products.get(state.productId);
  _expectTrue(product != null, 'product should read by id');
  product!
    ..stock = 6
    ..price = 119.99;
  await database.products.put(product);

  final productsById = await database.products.getAll([
    state.secondaryProductId,
    state.productId,
    999999,
  ]);
  _expect(
    productsById.map((product) => product?.sku).toList(),
    ['SKU-COFFEE', 'SKU-KEYBOARD', null],
    'getAll should preserve requested order',
  );

  final skuMatch = await database.products
      .where()
      .skuEqualTo('sku-keyboard')
      .findFirst();
  _expect(skuMatch?.dbId, state.productId, 'case-insensitive sku query');

  final lowStock = await database.products
      .filter()
      .activeEqualTo(true)
      .filter()
      .stockLessThanOrEqualTo(10)
      .sortByPrice()
      .limit(10)
      .findAll();
  _expect(
    lowStock.map((product) => product.sku).toList(),
    ['SKU-KEYBOARD'],
    'filtered sorted limited query should find low stock product',
  );

  final tagged = await database.products
      .filter()
      .tagsElementEqualTo('hardware')
      .findAll();
  _expect(tagged.single.dbId, state.productId, 'multi-entry tag query');

  final embedded = await database.customers
      .filter()
      .defaultShippingAddress((address) => address.cityEqualTo('Boston'))
      .findAll();
  _expect(embedded.single.dbId, state.customerId, 'embedded object query');

  final itemMatches = await database.orders
      .filter()
      .itemsElement((item) => item.skuEqualTo('SKU-KEYBOARD'))
      .findAll();
  _expect(itemMatches.single.dbId, state.orderId, 'embedded list query');

  final anyOfProducts = await database.products
      .filter()
      .anyOf([
        'SKU-KEYBOARD',
        'SKU-COFFEE',
      ], (query, sku) => query.skuEqualTo(sku))
      .sortBySku()
      .findAll();
  _expect(
    anyOfProducts.map((product) => product.sku).toList(),
    ['SKU-COFFEE', 'SKU-KEYBOARD'],
    'anyOf should OR product filters',
  );

  final allOfOrders = await database.orders
      .filter()
      .allOf(
        _OrderConstraint.values,
        (query, constraint) => switch (constraint) {
          _OrderConstraint.submitted => query.statusEqualTo(
            OrderStatus.submitted,
          ),
          _OrderConstraint.priority => query.priorityEqualTo(true),
        },
      )
      .findAll();
  _expect(allOfOrders.single.dbId, state.orderId, 'allOf should AND filters');

  final activeStockQuery = database.products.where().activeStockEqualTo(
    true,
    6,
  );
  _expect(
    await activeStockQuery.count(),
    1,
    'composite index query should count active stock',
  );

  final productNames = await database.products
      .all()
      .sortByName()
      .nameProperty()
      .findAll();
  _expect(productNames, [
    'Coffee Beans',
    'Mechanical Keyboard',
  ], 'property projection should return sorted names');

  final stockTotal = await database.products.all().stockProperty().sum();
  _expect(stockTotal, 70, 'numeric aggregate should sum stock');

  final averagePrice = await database.products.all().priceProperty().average();
  _expectTrue(
    averagePrice != null && averagePrice > 60,
    'numeric aggregate should average prices',
  );

  final splitWords = Cindel.splitWords('Real-world Cindel checkout');
  _expect(splitWords, [
    'real',
    'world',
    'cindel',
    'checkout',
  ], 'public text splitter should match word indexes');
}

Future<void> _runLinksAndBacklinks(
  CindelDatabase database,
  _ScenarioState state,
) async {
  final order = await database.orders.get(state.orderId);
  _expectTrue(order != null, 'order should read before loading links');
  await order!.customer.load();
  await order.payment.load();
  _expect(order.customer.value?.dbId, state.customerId, 'order customer link');
  _expect(order.payment.value?.dbId, state.paymentId, 'order payment link');

  final product = await database.products.get(state.productId);
  _expectTrue(product != null, 'product should read before loading link');
  await product!.category.load();
  _expect(
    product.category.value?.dbId,
    state.primaryCategoryId,
    'product category link',
  );

  final category = await database.categories.get(state.primaryCategoryId);
  await category!.products.load();
  _expect(
    category.products.map((product) => product.dbId).toList(),
    [state.productId],
    'category backlink should load products',
  );

  final customer = await database.customers.get(state.customerId);
  await customer!.orders.load();
  _expect(
    customer.orders.map((order) => order.dbId).toList(),
    [state.orderId],
    'customer backlink should load orders',
  );

  await product.category.reset();
  _expect(product.category.value, null, 'link reset should clear local value');
  await product.category.load();
  _expect(
    product.category.value?.dbId,
    state.primaryCategoryId,
    'link should load again after reset',
  );
}

Future<void> _runWatchers(CindelDatabase database, _ScenarioState state) async {
  final productEvents = <Product?>[];
  final lowStockEvents = <List<Product>>[];
  final lazyEvents = <void>[];
  final changeEvents = <CindelChangeSet>[];

  final productSubscription = database.products
      .watchObject(
        state.productId,
        pollInterval: const Duration(milliseconds: 5),
      )
      .listen(productEvents.add);
  final querySubscription = database.products
      .filter()
      .stockLessThanOrEqualTo(5)
      .watch(pollInterval: const Duration(milliseconds: 5))
      .listen(lowStockEvents.add);
  final lazySubscription = database.orders
      .watchCollectionLazy(
        pollInterval: const Duration(milliseconds: 5),
        fireImmediately: false,
      )
      .listen(lazyEvents.add);
  final changeSubscription = database
      .watchCollectionChanges(
        ProductSchema.name,
        pollInterval: const Duration(milliseconds: 5),
        fireImmediately: false,
      )
      .listen(changeEvents.add);

  try {
    await _waitUntil(() => productEvents.isNotEmpty);
    await _waitUntil(() => lowStockEvents.isNotEmpty);
    _expect(productEvents.last?.stock, 6, 'object watcher initial snapshot');
    _expect(lowStockEvents.last, <Product>[], 'query watcher initial snapshot');

    final product = await database.products.get(state.productId);
    product!.stock = 4;
    await database.products.put(product);

    await _waitUntil(() => productEvents.any((event) => event?.stock == 4));
    await _waitUntil(
      () => lowStockEvents.any(
        (event) => event.any((product) => product.dbId == state.productId),
      ),
    );
    await _waitUntil(
      () =>
          changeEvents.any((event) => event.mayAffectDocument(state.productId)),
    );

    final order = await database.orders.get(state.orderId);
    order!.status = OrderStatus.paid;
    await database.orders.put(order);
    await _waitUntil(() => lazyEvents.isNotEmpty);
  } finally {
    await productSubscription.cancel();
    await querySubscription.cancel();
    await lazySubscription.cancel();
    await changeSubscription.cancel();
  }
}

Future<void> _verifyPersistence(
  CindelDatabase database,
  _ScenarioState state,
) async {
  final order = await database.orders.get(state.orderId);
  _expect(order?.status, OrderStatus.paid, 'updated order should persist');
  await order!.customer.load();
  _expect(
    order.customer.value?.email.toLowerCase(),
    'ana@example.com',
    'customer link should persist',
  );

  final product = await database.products.get(state.productId);
  _expect(product?.stock, 4, 'updated product should persist');
  await product!.category.load();
  _expect(
    product.category.value?.dbId,
    state.primaryCategoryId,
    'category link should persist',
  );

  final settings = await database.appSettings
      .where()
      .keyEqualTo('checkout.enabled')
      .findFirst();
  _expect(settings?.enabled, true, 'settings should persist');
}

Future<void> _cleanup(CindelDatabase database, _ScenarioState state) async {
  await database.inventoryMovements.deleteAll(state.inventoryMovementIds);
  final deletedMovements = await database.inventoryMovements.getAll(
    state.inventoryMovementIds,
  );
  _expectTrue(
    deletedMovements.every((movement) => movement == null),
    'deleteAll should remove inventory movements',
  );

  await database.orders.delete(state.orderId);
  await database.payments.delete(state.paymentId);
  await database.products.deleteAll([
    state.productId,
    state.secondaryProductId,
  ]);
  await database.categories.deleteAll([
    state.primaryCategoryId,
    state.secondaryCategoryId,
  ]);
  await database.customers.delete(state.customerId);
}

CustomerAddress _customerAddress(
  String line1,
  String city,
  String country,
  int postalCode,
) {
  return CustomerAddress()
    ..line1 = line1
    ..city = city
    ..country = country
    ..postalCode = postalCode.toString()
    ..location = (CustomerGeoPoint()
      ..latitude = 42.3601
      ..longitude = -71.0589);
}

OrderAddress _orderAddress(
  String line1,
  String city,
  String country,
  int postalCode,
) {
  return OrderAddress()
    ..line1 = line1
    ..city = city
    ..country = country
    ..postalCode = postalCode.toString()
    ..location = (OrderGeoPoint()
      ..latitude = 42.3601
      ..longitude = -71.0589);
}

void _expect(Object? actual, Object? expected, String message) {
  if (!_deepEquals(actual, expected)) {
    throw CindelRealworldFailure(
      '$message. Expected <$expected>, got <$actual>.',
    );
  }
}

void _expectTrue(bool condition, String message) {
  if (!condition) {
    throw CindelRealworldFailure(message);
  }
}

bool _deepEquals(Object? left, Object? right) {
  if (identical(left, right)) {
    return true;
  }
  if (left is List && right is List) {
    if (left.length != right.length) {
      return false;
    }
    for (var i = 0; i < left.length; i += 1) {
      if (!_deepEquals(left[i], right[i])) {
        return false;
      }
    }
    return true;
  }
  return left == right;
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw CindelRealworldFailure('Timed out waiting for scenario event.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

enum _OrderConstraint { submitted, priority }
