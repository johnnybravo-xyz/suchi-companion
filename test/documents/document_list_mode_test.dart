import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/intl.dart';
import 'package:suchi_mobile/api/api_models.dart';
import 'package:suchi_mobile/api/suchi_client.dart';
import 'package:suchi_mobile/documents/document_list_mode.dart';
import 'package:suchi_mobile/documents/thumbnail_cache.dart';
import 'package:suchi_mobile/theme/suchi_theme.dart';
import 'package:suchi_mobile/widgets/suchi_widgets.dart';

void main() {
  testWidgets(
    'modes retain usable taps with distinct row and preview density',
    (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.close);
      final document = _document();
      final heights = <DocumentListMode, double>{};
      var taps = 0;

      for (final mode in DocumentListMode.values) {
        await _showRow(
          tester,
          fixture,
          document: document,
          mode: mode,
          onTap: () => taps++,
        );
        final row = find.byType(IndexRow);
        heights[mode] = tester.getSize(row).height;
        final expectedPreview = switch (mode) {
          DocumentListMode.standard => const Size(48, 56),
          DocumentListMode.compact => const Size(38, 44),
          DocumentListMode.detailed => const Size(72, 88),
        };
        expect(tester.getSize(find.byType(DocumentThumb)), expectedPreview);
        expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
        await tester.tap(row);
        await tester.pump();
      }

      expect(heights[DocumentListMode.standard], 78);
      expect(heights[DocumentListMode.compact], 66);
      expect(heights[DocumentListMode.detailed], 118);
      expect(taps, 3);
      expect(fixture.requests.map((uri) => uri.path), [
        '/api/documents/7/thumb',
      ]);
    },
  );

  testWidgets('Detailed exposes summary metadata and only three tags', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final fixture = _Fixture();
    addTearDown(fixture.close);
    final document = _document(
      correspondents: ['North Bank', 'Alex Smith', 'Not rendered'],
      tags: ['Tax year', 'Household', 'Original', 'Fourth tag', 'Fifth tag'],
    );
    await _showRow(
      tester,
      fixture,
      document: document,
      mode: DocumentListMode.detailed,
    );

    final date = DateFormat.yMMMd().format(
      DateTime.fromMillisecondsSinceEpoch(
        document.createdAt * 1000,
        isUtc: true,
      ).toLocal(),
    );
    expect(find.text('Finance · Statements'), findsOneWidget);
    expect(find.text(date), findsOneWidget);
    expect(find.text('North Bank, Alex Smith'), findsOneWidget);
    expect(find.text('Tax year'), findsOneWidget);
    expect(find.text('Household'), findsOneWidget);
    expect(find.text('Original'), findsOneWidget);
    expect(find.text('+2'), findsOneWidget);
    expect(find.textContaining('Not rendered'), findsNothing);
    expect(find.text('Fourth tag'), findsNothing);
    final label = tester.getSemantics(find.byType(IndexRow)).label;
    for (final value in [
      document.title,
      'category 12',
      'Internal',
      'Finance · Statements',
      date,
      'North Bank, Alex Smith',
      'Tax year',
      'Household',
      'Original',
      '+2',
    ]) {
      expect(label, contains(value));
    }
    expect(label, isNot(contains('Fourth tag')));
    expect(fixture.requests.map((uri) => uri.path), ['/api/documents/7/thumb']);
    semantics.dispose();
  });

  for (final sensitivity in ['confidential', 'restricted']) {
    testWidgets('$sensitivity stays concealed through every view change', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final fixture = _Fixture();
      addTearDown(fixture.close);
      final document = _document(
        sensitivity: sensitivity,
        correspondents: ['Private person'],
        tags: ['Private tag'],
      );
      for (final mode in DocumentListMode.values) {
        await _showRow(tester, fixture, document: document, mode: mode);
        expect(find.byIcon(Icons.lock_outline), findsOneWidget);
        expect(find.textContaining('preview hidden'), findsOneWidget);
        expect(find.textContaining('Private person'), findsNothing);
        expect(find.textContaining('Private tag'), findsNothing);
        final label = tester.getSemantics(find.byType(IndexRow)).label;
        expect(label, contains(sensitivityLabel(sensitivity)));
        expect(label, contains('Statements'));
        expect(label, isNot(contains('Private person')));
        expect(label, isNot(contains('Private tag')));
        if (mode == DocumentListMode.detailed) {
          expect(find.text('Finance · Statements'), findsOneWidget);
        }
      }
      expect(fixture.requests, isEmpty);
      expect(fixture.cache.byteCount, 0);
      semantics.dispose();
    });
  }

  for (final mode in DocumentListMode.values) {
    testWidgets('$mode mutation disables taps and restores the row action', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final fixture = _Fixture();
      addTearDown(fixture.close);
      var taps = 0;
      final document = _document();
      await _showRow(
        tester,
        fixture,
        document: document,
        mode: mode,
        enabled: false,
        onTap: () => taps++,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final busyData = tester
          .getSemantics(find.byType(IndexRow))
          .getSemanticsData();
      expect(busyData.hasAction(SemanticsAction.tap), isFalse);
      expect(busyData.flagsCollection.isEnabled, Tristate.isFalse);
      await tester.tap(find.byType(IndexRow));
      await tester.pump();
      expect(taps, 0);

      await _showRow(
        tester,
        fixture,
        document: document,
        mode: mode,
        onTap: () => taps++,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      final readyData = tester
          .getSemantics(find.byType(IndexRow))
          .getSemanticsData();
      expect(readyData.hasAction(SemanticsAction.tap), isTrue);
      expect(readyData.flagsCollection.isEnabled, Tristate.isTrue);
      await tester.tap(find.byType(IndexRow));
      await tester.pump();
      expect(taps, 1);
      semantics.dispose();
    });

    testWidgets(
      '$mode grows for long text at 200 percent without losing title',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final fixture = _Fixture();
        addTearDown(fixture.close);
        final document = _document(
          title:
              'A long annual financial statement with an important full title '
              'that must remain available to assistive technology',
          correspondents: [
            'A correspondent with a long organization name',
            'Another organization with a similarly long name',
          ],
          tags: [
            'A long tag that needs to wrap inside its chip',
            'Another multiword tag',
            'Archive',
            'Hidden fourth tag',
          ],
        );
        var taps = 0;
        await _showRow(
          tester,
          fixture,
          document: document,
          mode: mode,
          onTap: () => taps++,
        );
        final originalHeight = tester.getSize(find.byType(IndexRow)).height;
        await _showRow(
          tester,
          fixture,
          document: document,
          mode: mode,
          textScale: 2,
          onTap: () => taps++,
        );
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byType(IndexRow)).height,
          greaterThan(originalHeight),
        );
        expect(
          tester.getSemantics(find.byType(IndexRow)).label,
          contains(document.title),
        );
        if (mode == DocumentListMode.detailed) {
          expect(
            find.text('A long tag that needs to wrap inside its chip'),
            findsOneWidget,
          );
        }
        await tester.tap(find.text(document.title));
        await tester.pump();
        expect(taps, 1);
        semantics.dispose();
      },
    );
  }
}

Future<void> _showRow(
  WidgetTester tester,
  _Fixture fixture, {
  required DocumentSummary document,
  required DocumentListMode mode,
  bool enabled = true,
  double textScale = 1,
  VoidCallback? onTap,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: SuchiTheme.light,
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
            size: const Size(390, 844),
            textScaler: TextScaler.linear(textScale),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: SuchiCard(
              child: IndexRow(
                key: const ValueKey('document'),
                document: document,
                client: fixture.client,
                cache: fixture.cache,
                mode: mode,
                enabled: enabled,
                onTap: onTap ?? () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  // The real thumbnail request resolves, without settling a mutation spinner.
  await tester.pump();
  await tester.pump();
}

DocumentSummary _document({
  String title = 'Statement',
  String sensitivity = 'internal',
  List<String> correspondents = const [],
  List<String> tags = const [],
}) => DocumentSummary.fromJson({
  'id': 7,
  'title': title,
  'created_at': 1704110400,
  'updated_at': 1704110400,
  'jd_category_id': 1,
  'jd_category_code': 12,
  'jd_category_name': 'Statements',
  'jd_area_name': 'Finance',
  'sensitivity': sensitivity,
  'tags': tags,
  'correspondents': correspondents,
});

final class _Fixture {
  _Fixture() {
    transport = MockClient((request) async {
      requests.add(request.url);
      return http.Response('', 404);
    });
    client = SuchiClient(
      origin: Uri.parse('https://suchi.example.com'),
      token: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      httpClient: transport,
    );
  }

  final requests = <Uri>[];
  final cache = ThumbnailMemoryCache();
  late final MockClient transport;
  late final SuchiClient client;

  void close() {
    cache.clear();
    client.close();
    transport.close();
  }
}
