import '../models/precomputed_catalog.dart';
import '../models/category.dart';
import '../models/book.dart';
import '../models/author.dart';

/// Extension functions for working with PrecomputedCatalog
extension PrecomputedCatalogExtensions on PrecomputedCatalog {
  /// Extracts all root categories from the precomputed catalog.
  List<Category> extractRootCategories() {
    return rootCategories.map((cat) => cat.toCategory()).toList();
  }

  /// Extracts all books from the precomputed catalog into a flat set.
  Set<Book> extractAllBooks() {
    final books = <Book>{};

    void traverseCategory(CatalogCategory cat) {
      // Add books from this category
      books.addAll(cat.books.map((b) => b.toBook()));
      // Traverse subcategories
      for (final subcategory in cat.subcategories) {
        traverseCategory(subcategory);
      }
    }

    for (final rootCat in rootCategories) {
      traverseCategory(rootCat);
    }
    return books;
  }

  /// Extracts the category children map from the precomputed catalog.
  /// Maps category ID to its direct children.
  Map<int, List<Category>> extractCategoryChildren() {
    final childrenMap = <int, List<Category>>{};

    void traverseCategory(CatalogCategory cat) {
      if (cat.subcategories.isNotEmpty) {
        childrenMap[cat.id] = cat.subcategories.map((c) => c.toCategory()).toList();
      }
      for (final subcategory in cat.subcategories) {
        traverseCategory(subcategory);
      }
    }

    for (final rootCat in rootCategories) {
      traverseCategory(rootCat);
    }
    return childrenMap;
  }

  /// Finds a category by ID in the catalog tree.
  CatalogCategory? findCategoryById(int categoryId) {
    CatalogCategory? searchInCategory(CatalogCategory cat) {
      if (cat.id == categoryId) return cat;
      for (final subcategory in cat.subcategories) {
        final found = searchInCategory(subcategory);
        if (found != null) return found;
      }
      return null;
    }

    for (final rootCat in rootCategories) {
      final found = searchInCategory(rootCat);
      if (found != null) return found;
    }
    return null;
  }

  /// Finds a book by ID in the catalog tree.
  CatalogBook? findBookById(int bookId) {
    CatalogBook? searchInCategory(CatalogCategory cat) {
      final book = cat.books.where((b) => b.id == bookId).firstOrNull;
      if (book != null) return book;

      for (final subcategory in cat.subcategories) {
        final found = searchInCategory(subcategory);
        if (found != null) return found;
      }
      return null;
    }

    for (final rootCat in rootCategories) {
      final found = searchInCategory(rootCat);
      if (found != null) return found;
    }
    return null;
  }

  /// Gets all books in a specific category (non-recursive).
  List<CatalogBook> getBooksInCategory(int categoryId) {
    final category = findCategoryById(categoryId);
    return category?.books ?? [];
  }

  /// Gets the path from root to a given category.
  List<CatalogCategory> getCategoryPath(int categoryId) {
    final path = <CatalogCategory>[];

    bool findPathInCategory(CatalogCategory cat, int target) {
      if (cat.id == target) {
        path.add(cat);
        return true;
      }

      for (final subcategory in cat.subcategories) {
        if (findPathInCategory(subcategory, target)) {
          path.insert(0, cat); // Add to front to build path from root
          return true;
        }
      }
      return false;
    }

    for (final rootCat in rootCategories) {
      if (findPathInCategory(rootCat, categoryId)) {
        break;
      }
    }

    return path;
  }
}

/// Extension for converting CatalogCategory to Category model.
extension CatalogCategoryExtensions on CatalogCategory {
  Category toCategory() {
    return Category(
      id: id,
      parentId: parentId,
      title: title,
      level: level,
    );
  }
}

/// Extension for converting CatalogBook to Book model.
extension CatalogBookExtensions on CatalogBook {
  Book toBook() {
    return Book(
      id: id,
      categoryId: categoryId,
      sourceId: 0, // Will need to be populated separately if needed
      title: title,
      authors: authors.map((name) => Author(name: name)).toList(),
      pubPlaces: const [],
      pubDates: const [],
      heShortDesc: null,
      notesContent: null,
      order: order,
      topics: const [],
      totalLines: totalLines,
      isBaseBook: isBaseBook,
      hasTargumConnection: hasTargumConnection,
      hasReferenceConnection: hasReferenceConnection,
      hasCommentaryConnection: hasCommentaryConnection,
      hasOtherConnection: hasOtherConnection,
    );
  }
}
