# Cindel Shop Lite

Cindel Shop Lite is a small offline store demo built to show how Cindel behaves
inside a practical Flutter app: local catalog data, filtering, pagination,
dashboard metrics, a cart, and a simulated checkout that updates product stock.

[Overview](#overview) |
[Features](#features) |
[Architecture](#architecture) |
[Cindel Usage](#cindel-usage) |
[Run](#run) |
[Development](#development)

> This is not a payment app. Checkout is intentionally simulated so the demo can
> focus on local data correctness, transactions, and UI updates.

## Overview

The app models a lightweight shop/inventory workflow:

- The catalog is seeded locally on first launch.
- Products can be searched, filtered, sorted, and paginated.
- Products can be added to an in-memory cart.
- Checkout validates current stock and updates products inside a Cindel write
  transaction.
- Dashboard metrics refresh after stock changes.

The goal is to demonstrate Cindel with a familiar app shape instead of a minimal
CRUD screen.

## Features

- Catalog with 100 generated demo products.
- Freezed product model annotated as a Cindel collection.
- Indexed search, category filters, stock filters, sorting, and pagination.
- Dashboard with inventory value, category stock, low-stock counts, and critical
  products.
- Cart with quantity controls and stock-aware limits.
- Simulated checkout that decrements product stock.
- Riverpod providers and hooks-based presentation widgets.
- Flutter localization using ARB files.

## Screens

### Dashboard

Shows a compact overview of the local catalog:

- total products,
- category count,
- low-stock and out-of-stock counts,
- inventory value,
- stock by category,
- critical stock list.

### Catalog

Shows the seeded products using a paginated grid. The catalog supports:

- text search,
- category filtering,
- stock-only filtering,
- sort modes,
- add-to-cart actions.

### Shopping / Checkout

Shows the current cart and lets the user:

- increase or decrease quantities,
- remove items,
- review subtotal,
- simulate checkout.

Checkout writes the updated product stock to Cindel and clears the cart when the
operation succeeds.

## Architecture

The app follows the same feature-first structure used by the rest of the Cindel
examples:

```text
lib/
  features/
    catalog/
      data/
      di/
      domain/
      presentation/
    dashboard/
      data/
      di/
      domain/
      presentation/
    shopping/
      data/
      di/
      domain/
      presentation/
    shared/
```

The main boundaries are:

- `domain`: entities, repository contracts, failures, and use cases.
- `data`: local Cindel datasources and repository implementations.
- `di`: Riverpod provider wiring for feature dependencies.
- `presentation`: pages, providers, widgets, and UI helpers.

## Cindel Usage

Shop Lite demonstrates these Cindel concepts:

- `@Collection` models using Freezed primary factory style.
- Generated typed collections through `ProductSchema`.
- Indexed queries for search, category, price, stock, and tags.
- Sorting and offset/limit pagination.
- Count queries for dashboard and startup checks.
- Bulk writes through `putAll`.
- Explicit `writeTxn` during checkout.
- Local persistent database opening through `Cindel.open`.

The database is opened with:

```dart
final database = await Cindel.open(
  directory: databaseDirectory.path,
  schemas: [ProductSchema],
);
```

Checkout uses a write transaction so stock validation and stock updates stay in
one operation:

```dart
await database.writeTxn(() async {
  // Read current products, validate stock, then put updated products.
});
```

## Run

Install dependencies:

```sh
flutter pub get
```

Generate code:

```sh
dart run build_runner build
flutter gen-l10n
```

Run a flavor:

```sh
flutter run --flavor development --target lib/main_development.dart
flutter run --flavor staging --target lib/main_staging.dart
flutter run --flavor production --target lib/main_production.dart
```

## Development

Analyze the app:

```sh
dart analyze
```

Regenerate Riverpod, Freezed, and Cindel code after changing annotated models or
providers:

```sh
dart run build_runner build
```

Regenerate localizations after changing ARB files:

```sh
flutter gen-l10n
```

The English ARB file is the template:

```text
lib/l10n/arb/app_en.arb
```

Spanish is configured as a supported locale, but untranslated strings currently
fall back to the English template values.

## License

This example is part of the Cindel repository. See the repository license for
details.
