// Adapters to convert between otzaria models and migration models
// This allows seamless integration between the existing codebase and the new database layer

import 'package:otzaria/models/books.dart' as otzaria_models;
import 'package:otzaria/library/models/library.dart' as otzaria_lib;
import 'package:otzaria/migration/core/models/book.dart' as migration_models;
import 'package:otzaria/migration/core/models/category.dart'
    as migration_models;
import 'package:otzaria/migration/core/models/line.dart' as migration_models;
import 'package:otzaria/migration/core/models/toc_entry.dart'
    as migration_models;

/// Converts a migration Book to an otzaria TextBook
otzaria_models.TextBook migrationBookToOtzariaBook(
  migration_models.Book migrationBook,
  otzaria_lib.Category? category,
) {
  return otzaria_models.TextBook(
    title: migrationBook.title,
    category: category,
    author: migrationBook.authors.isNotEmpty
        ? migrationBook.authors.first.name
        : null,
    heShortDesc: migrationBook.heShortDesc,
    pubDate: migrationBook.pubDates.isNotEmpty
        ? migrationBook.pubDates.first.date
        : null,
    pubPlace: migrationBook.pubPlaces.isNotEmpty
        ? migrationBook.pubPlaces.first.name
        : null,
    order: migrationBook.order.toInt(),
    topics: migrationBook.topics.map((t) => t.name).join(', '),
  );
}

/// Converts a migration TocEntry to an otzaria TocEntry
otzaria_models.TocEntry migrationTocToOtzariaToc(
  migration_models.TocEntry migrationToc,
  otzaria_models.TocEntry? parent,
) {
  final otzariaToc = otzaria_models.TocEntry(
    text: migrationToc.text,
    index: migrationToc.lineIndex ?? 0,
    level: migrationToc.level,
    parent: parent,
  );

  return otzariaToc;
}

/// Converts a list of migration Lines to a single text string
String migrationLinesToText(List<migration_models.Line> lines) {
  return lines.map((line) => line.content).join('\n');
}

/// Converts a migration Category to an otzaria Category
otzaria_lib.Category migrationCategoryToOtzariaCategory(
  migration_models.Category migrationCategory,
  otzaria_lib.Category? parent,
) {
  return otzaria_lib.Category(
    title: migrationCategory.title,
    description: '',
    shortDescription: '',
    order: 999,
    subCategories: [],
    books: [],
    parent: parent,
  );
}
