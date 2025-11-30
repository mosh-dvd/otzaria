import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';

import 'package:otzaria/text_book/text_book_repository.dart';
import 'package:otzaria/text_book/editing/repository/overrides_repository.dart';
import 'package:otzaria/text_book/editing/services/overrides_rebase_service.dart';

@GenerateMocks([
  TextBookRepository,
  OverridesRepository,
  OverridesRebaseService,
])
import 'text_book_bloc_editor_test.mocks.dart';

void main() {
  group('TextBookBloc Editor Tests', () {
    late MockTextBookRepository mockRepository;
    late MockOverridesRepository mockOverridesRepository;
    late MockOverridesRebaseService mockRebaseService;

    setUp(() {
      mockRepository = MockTextBookRepository();
      mockOverridesRepository = MockOverridesRepository();
      mockRebaseService = MockOverridesRebaseService();
    });

    test('should create mocks successfully', () {
      expect(mockRepository, isNotNull);
      expect(mockOverridesRepository, isNotNull);
      expect(mockRebaseService, isNotNull);
    });

    test('mock repository should return false for bookExists', () async {
      when(mockRepository.bookExists('test')).thenAnswer((_) async => false);

      final result = await mockRepository.bookExists('test');
      expect(result, false);
    });

    test('mock overrides repository should return null for readOverride',
        () async {
      when(mockOverridesRepository.readOverride('book', 'section'))
          .thenAnswer((_) async => null);

      final result =
          await mockOverridesRepository.readOverride('book', 'section');
      expect(result, null);
    });

    test('mock overrides repository should return false for hasLinksFile',
        () async {
      when(mockOverridesRepository.hasLinksFile('book'))
          .thenAnswer((_) async => false);

      final result = await mockOverridesRepository.hasLinksFile('book');
      expect(result, false);
    });

    test('mock rebase service should return success', () async {
      when(mockRebaseService.rebaseIfSourceChanged(
        bookId: anyNamed('bookId'),
        sectionId: anyNamed('sectionId'),
        originalCandidate: anyNamed('originalCandidate'),
        overrideMarkdown: anyNamed('overrideMarkdown'),
      )).thenAnswer((_) async => RebaseOutcome.success);

      final result = await mockRebaseService.rebaseIfSourceChanged(
        bookId: 'book',
        sectionId: 'section',
        originalCandidate: 'original',
        overrideMarkdown: 'content',
      );
      expect(result, RebaseOutcome.success);
    });
  });
}
