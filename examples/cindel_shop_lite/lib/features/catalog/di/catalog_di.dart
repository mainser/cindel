import 'dart:io';

import 'package:cindel/cindel.dart';
import 'package:cindel_shop_lite/features/catalog/data/datasources/catalog_local_data_source.dart';
import 'package:cindel_shop_lite/features/catalog/data/repositories/cindel_catalog_repository.dart';
import 'package:cindel_shop_lite/features/catalog/domain/entities/product.dart';
import 'package:cindel_shop_lite/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:cindel_shop_lite/features/catalog/domain/usecases/count_catalog_products.dart';
import 'package:cindel_shop_lite/features/catalog/domain/usecases/ensure_catalog_seeded.dart';
import 'package:cindel_shop_lite/features/catalog/domain/usecases/watch_catalog_products.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'catalog_di.g.dart';

@riverpod
Future<CindelDatabase> catalogDatabase(Ref ref) async {
  final supportDirectory = await _applicationSupportDirectory();
  final databaseDirectory = cindelShopLiteDatabaseDirectory(supportDirectory);
  final database = await Cindel.open(
    directory: databaseDirectory.path,
    schemas: [ProductSchema],
  );
  ref.onDispose(database.close);
  return database;
}

Directory cindelShopLiteDatabaseDirectory(Directory supportDirectory) {
  return Directory(
    '${supportDirectory.path}${Platform.pathSeparator}cindel_shop_lite',
  );
}

@riverpod
CatalogLocalDataSource catalogLocalDataSource(Ref ref) {
  return CatalogLocalDataSource(ref.watch(catalogDatabaseProvider.future));
}

@riverpod
CatalogRepository catalogRepository(Ref ref) {
  return CindelCatalogRepository(ref.watch(catalogLocalDataSourceProvider));
}

@riverpod
EnsureCatalogSeeded ensureCatalogSeededUseCase(Ref ref) {
  return EnsureCatalogSeeded(ref.watch(catalogRepositoryProvider));
}

@riverpod
WatchCatalogProducts watchCatalogProductsUseCase(Ref ref) {
  return WatchCatalogProducts(ref.watch(catalogRepositoryProvider));
}

@riverpod
CountCatalogProducts countCatalogProductsUseCase(Ref ref) {
  return CountCatalogProducts(ref.watch(catalogRepositoryProvider));
}

Future<Directory> _applicationSupportDirectory() async {
  if (!Platform.isWindows) {
    return getApplicationSupportDirectory();
  }

  final appDataPath =
      Platform.environment['APPDATA'] ?? Platform.environment['LOCALAPPDATA'];
  if (appDataPath == null || appDataPath.trim().isEmpty) {
    throw StateError('Windows application data directory is unavailable.');
  }
  return Directory('$appDataPath${Platform.pathSeparator}Cindel');
}
