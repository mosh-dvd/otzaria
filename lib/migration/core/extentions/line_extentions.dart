import '../models/line.dart';
import '../models/line_toc_mapping.dart';

/// Extensions to facilitate the transition to the new structure without tocEntryId.
extension LineExtensions on Line {
  /// Retrieves the first TOC entry associated with this line
  /// (to be used with a list of LineTocMapping).
  ///
  /// [mappings] The list of line-to-TOC mappings to search in.
  /// Returns the ID of the first TOC entry associated with this line, or null if none found.
  int? findTocEntryId(List<LineTocMapping> mappings) {
    try {
      // find the first mapping where the lineId matches this line's id.
      final mapping = mappings.firstWhere(
        (it) => it.lineId == id,
      );
      return mapping.tocEntryId;
    } catch (e) {
      // firstWhere throws if no element is found.
      return null;
    }
  }

  /// Checks if this line has an associated TOC entry.
  ///
  /// [mappings] The list of line-to-TOC mappings to search in.
  /// Returns true if this line has an associated TOC entry, false otherwise.
  bool hasTocEntry(List<LineTocMapping> mappings) {
    // Check if any mapping's lineId matches this line's id.
    return mappings.any((it) => it.lineId == id);
  }
}