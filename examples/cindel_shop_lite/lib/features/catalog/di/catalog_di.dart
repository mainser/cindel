import 'dart:io';

import 'package:cindel/cindel.dart';
import 'package:cindel_shop_lite/features/catalog/data/datasources/catalog_local_data_source.dart';
import 'package:cindel_shop_lite/features/catalog/data/repositories/cindel_catalog_repository.dart';
import 'package:cindel_shop_lite/features/catalog/domain/entities/product.dart';
import 'package:cindel_shop_lite/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:cindel_shop_lite/features/catalog/domain/usecases/count_catalog_products.dart';
import 'package:cindel_shop_lite/features/catalog/domain/usecases/ensure_catalog_seeded.dart';
import 'package:cindel_shop_lite/features/catalog/domain/usecases/read_catalog_products_page.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'catalog_di.g.dart';

/// Opens the local Cindel database used by the demo catalog.
///
/// The app registers only [ProductSchema] today, so catalog, dashboard, and
/// checkout all operate over the same typed products collection.
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

/// Builds the stable application-support path for the Shop Lite database.
Directory cindelShopLiteDatabaseDirectory(Directory supportDirectory) {
  return Directory(
    '${supportDirectory.path}${Platform.pathSeparator}cindel_shop_lite',
  );
}

/// Provides the catalog data source backed by the shared Cindel database.
@riverpod
CatalogLocalDataSource catalogLocalDataSource(Ref ref) {
  return CatalogLocalDataSource(ref.watch(catalogDatabaseProvider.future));
}

/// Provides the catalog repository used by catalog-facing use cases.
@riverpod
CatalogRepository catalogRepository(Ref ref) {
  return CindelCatalogRepository(ref.watch(catalogLocalDataSourceProvider));
}

/// Use case that inserts deterministic demo products when the database is new.
@riverpod
EnsureCatalogSeeded ensureCatalogSeededUseCase(Ref ref) {
  return EnsureCatalogSeeded(ref.watch(catalogRepositoryProvider));
}

/// Use case for paginated catalog reads.
@riverpod
ReadCatalogProductsPage readCatalogProductsPageUseCase(Ref ref) {
  return ReadCatalogProductsPage(ref.watch(catalogRepositoryProvider));
}

/// Use case for lightweight catalog counts used by UI badges and startup.
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
