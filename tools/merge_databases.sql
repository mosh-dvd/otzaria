-- Script to merge my_books.db into seforim.db
-- Usage: sqlite3 seforim.db < tools/merge_databases.sql

-- Attach the personal database
ATTACH DATABASE 'my_books.db' AS personal;

-- Get max IDs (for reference)
.print "Current max IDs in seforim.db:"
SELECT 'Books: ' || MAX(id) FROM book;
SELECT 'Lines: ' || MAX(id) FROM line;
SELECT 'TOC Entries: ' || MAX(id) FROM tocEntry;
SELECT 'TOC Texts: ' || MAX(id) FROM tocText;
SELECT 'Categories: ' || MAX(id) FROM category;

.print ""
.print "Books in my_books.db:"
SELECT 'Count: ' || COUNT(*) FROM personal.book;

-- Create temporary offset variables
-- We'll add these offsets to all IDs from personal database

-- Copy categories first (with offset)
INSERT OR IGNORE INTO category (id, parentId, title, level)
SELECT 
  id + 10000,  -- Offset for category IDs
  CASE WHEN parentId IS NOT NULL THEN parentId + 10000 ELSE NULL END,
  title,
  level
FROM personal.category;

-- Copy books (with offset)
INSERT INTO book (
  id, categoryId, sourceId, title, heShortDesc, notesContent,
  orderIndex, totalLines, isBaseBook, hasTargumConnection,
  hasReferenceConnection, hasCommentaryConnection, hasOtherConnection
)
SELECT 
  id + 100000,  -- Offset for book IDs
  categoryId + 10000,  -- Reference to offset category
  sourceId,
  title,
  heShortDesc,
  notesContent,
  orderIndex,
  totalLines,
  isBaseBook,
  hasTargumConnection,
  hasReferenceConnection,
  hasCommentaryConnection,
  hasOtherConnection
FROM personal.book;

-- Copy TOC texts (with offset, avoid duplicates)
INSERT OR IGNORE INTO tocText (id, text)
SELECT 
  id + 100000,  -- Offset for tocText IDs
  text
FROM personal.tocText;

-- Copy lines (with offset)
INSERT INTO line (id, bookId, lineIndex, content, tocEntryId)
SELECT 
  id + 10000000,  -- Offset for line IDs (large offset!)
  bookId + 100000,  -- Reference to offset book
  lineIndex,
  content,
  CASE WHEN tocEntryId IS NOT NULL THEN tocEntryId + 100000 ELSE NULL END
FROM personal.line;

-- Copy TOC entries (with offset)
INSERT INTO tocEntry (
  id, bookId, parentId, textId, level, lineId,
  isLastChild, hasChildren
)
SELECT 
  id + 100000,  -- Offset for tocEntry IDs
  bookId + 100000,  -- Reference to offset book
  CASE WHEN parentId IS NOT NULL THEN parentId + 100000 ELSE NULL END,
  textId + 100000,  -- Reference to offset tocText
  level,
  CASE WHEN lineId IS NOT NULL THEN lineId + 10000000 ELSE NULL END,
  isLastChild,
  hasChildren
FROM personal.tocEntry;

-- Verify the merge
.print ""
.print "After merge:"
SELECT 'Total books: ' || COUNT(*) FROM book;
SELECT 'Total lines: ' || COUNT(*) FROM line;
SELECT 'Total TOC entries: ' || COUNT(*) FROM tocEntry;

-- Detach personal database
DETACH DATABASE personal;

.print ""
.print "✅ Merge completed successfully!"
.print "Your personal books are now in seforim.db"
