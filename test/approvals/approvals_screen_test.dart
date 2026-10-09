import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:suchi_companion/api/suchi_client.dart';
import 'package:suchi_companion/approvals/approvals_controller.dart';
import 'package:suchi_companion/approvals/approvals_screen.dart';
import 'package:suchi_companion/auth/session_controller.dart';
import 'package:suchi_companion/detail/document_detail_screen.dart';
import 'package:suchi_companion/shell/shell.dart';
import 'package:suchi_companion/theme/suchi_theme.dart';
import 'package:suchi_companion/widgets/suchi_widgets.dart';

import '../support/mobile_app_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MobileAppHarness harness;
  late _ReviewBackend backend;

  setUp(() async {
    backend = _ReviewBackend();
    harness = MobileAppHarness();
    await harness.initialize(
      transportFactory: () => MockClient(backend.handle),
    );
  });

  tearDown(() async {
    await harness.close();
  });

  testWidgets(
    'pending Inbox card opens approvals while the profile avatar stays inert',
    (tester) async {
      await _pumpShell(
        tester,
        harness,
        size: const Size(320, 700),
        textScale: 1,
      );

      expect(find.byType(SuchiPageHeader), findsOneWidget);
      expect(find.byType(CircleAvatar), findsOneWidget);
      expect(
        find.byKey(const ValueKey('approvals-inbox-card')),
        findsOneWidget,
      );
      expect(find.text('5 filings need your approval'), findsOneWidget);
      expect(find.textContaining('Suchi suggested'), findsNothing);
      expect(find.byIcon(Icons.compare_arrows), findsNothing);
      final cardBounds = tester.getRect(
        find.byKey(const ValueKey('approvals-inbox-card')),
      );
      expect(cardBounds.height, greaterThanOrEqualTo(80));
      expect(tester.takeException(), isNull);

      await tester.tap(find.byType(CircleAvatar));
      await tester.pumpAndSettle();
      expect(find.byType(ApprovalsScreen), findsNothing);

      await tester.tap(find.byKey(const ValueKey('approvals-inbox-card')));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 2),
      );

      expect(find.byType(ApprovalsScreen), findsOneWidget);
      expect(
        ModalRoute.of(tester.element(find.byType(ApprovalsScreen)))
            ?.settings
            .name,
        '/approvals',
      );
      expect(find.text('Account 7 electricity bill'), findsOneWidget);
      expect(find.text('Supplier invoice'), findsNothing);
      expect(find.text('Below review threshold'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('open-approval-document-93')));
      await tester.pumpAndSettle();
      expect(find.byType(DocumentDetailScreen), findsOneWidget);
      expect(
        ModalRoute.of(tester.element(find.byType(DocumentDetailScreen)))
            ?.settings
            .name,
        '/documents/93',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('document-change-approval-306')),
        400,
        scrollable: find.byType(Scrollable),
      );
      await tester.pumpAndSettle();
      expect(find.text('Service agreement'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('date-approval-401')),
        400,
        scrollable: find.byType(Scrollable),
      );
      await tester.pumpAndSettle();
      expect(find.text('Renewal date'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Documents').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('approvals-inbox-card')), findsNothing);
      expect(find.byType(CircleAvatar), findsOneWidget);
      await tester.tap(find.byType(CircleAvatar));
      await tester.pumpAndSettle();
      expect(find.byType(ApprovalsScreen), findsNothing);

      await tester.tap(find.text('Inbox').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('approvals-inbox-card')));
      await tester.pumpAndSettle();
      expect(
        ModalRoute.of(tester.element(find.byType(ApprovalsScreen)))
            ?.settings
            .name,
        '/approvals',
      );
      await tester.runAsync(harness.services.session.signOut);
      await tester.pumpAndSettle();
      expect(find.byType(ApprovalsScreen), findsNothing);
      expect(find.text('Signed out'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _unmountShell(tester);
    },
  );

  testWidgets('approval cards fit a 320px viewport at 200% text', (
    tester,
  ) async {
    final controller = ApprovalsController(session: harness.services.session);
    addTearDown(controller.dispose);
    await controller.reload();
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: SuchiTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: ApprovalsScreen(
          controller: controller,
          session: harness.services.session,
          identity: harness.services.session.identity!,
          client: harness.services.session.client!,
          onOpenDocument: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('document-change-approval-301')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('document-change-approval-302')),
      400,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();
    expect(find.text('Add tag: Renewals'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('document-change-approval-305')),
      400,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unfiled'), findsOneWidget);
    expect(find.text('12 Banking'), findsOneWidget);
    final categoryCard = find.byKey(
      const ValueKey('document-change-approval-305'),
    );
    final currentCategory = find.descendant(
      of: categoryCard,
      matching: find.text('Unfiled'),
    );
    final transitionArrow = find.descendant(
      of: categoryCard,
      matching: find.text('→'),
    );
    final proposedCategory = find.descendant(
      of: categoryCard,
      matching: find.text('12 Banking'),
    );
    expect(
      tester.getTopLeft(currentCategory).dy,
      tester.getTopLeft(transitionArrow).dy,
    );
    expect(
      tester.getTopLeft(proposedCategory).dy,
      tester.getTopLeft(transitionArrow).dy,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('document-change-details-305')),
      300,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(find.byKey(const ValueKey('document-change-details-305')));
    await tester.pumpAndSettle();
    expect(find.text('Why this was suggested'), findsOneWidget);
    expect(find.text('Archive match'), findsOneWidget);
    final explanationLabel = find.descendant(
      of: categoryCard,
      matching: find.text('Why this was suggested'),
    );
    final explanationValue = find.descendant(
      of: categoryCard,
      matching: find.text('Archive match'),
    );
    expect(
      tester.getTopLeft(explanationLabel).dy,
      tester.getTopLeft(explanationValue).dy,
    );
    expect(find.text('Similar documents'), findsOneWidget);
    expect(find.text('Reason'), findsNothing);
    expect(find.text('Threshold'), findsNothing);
    expect(find.text('Evidence'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('date-approval-401')),
      400,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();
    expect(find.text('Renewal date'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _unmountShell(tester);
  });

  testWidgets('cards remain until confirmed and use exact review decisions', (
    tester,
  ) async {
    await _pumpShell(tester, harness);
    await tester.tap(find.byKey(const ValueKey('approvals-inbox-card')));
    await tester.pumpAndSettle();

    final pendingMutation = Completer<http.Response>();
    backend.nextDocumentChangeMutation = pendingMutation;
    await tester.tap(find.byKey(const ValueKey('accept-document-change-301')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('document-change-approval-301')),
      findsOneWidget,
    );
    expect(
      jsonDecode(
        backend.singleRequest('POST', '/api/approvals/tasks/301/resolve').body,
      ),
      {'choice': 'apply'},
    );

    pendingMutation.complete(http.Response('', 204));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('document-change-approval-301')),
      findsNothing,
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('dismiss-document-change-302')),
      400,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(find.byKey(const ValueKey('dismiss-document-change-302')));
    await tester.pumpAndSettle();
    expect(
      jsonDecode(
        backend.singleRequest('POST', '/api/approvals/tasks/302/resolve').body,
      ),
      {'choice': 'reject'},
    );
    expect(
      find.byKey(const ValueKey('document-change-approval-302')),
      findsNothing,
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('accept-document-change-305')),
      400,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('accept-document-change-305')));
    await tester.pumpAndSettle();
    expect(
      jsonDecode(
        backend.singleRequest('POST', '/api/approvals/tasks/305/resolve').body,
      ),
      {'choice': 'apply'},
    );
    expect(
      find.byKey(const ValueKey('document-change-approval-305')),
      findsNothing,
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('accept-document-change-306')),
      400,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('accept-document-change-306')));
    await tester.pumpAndSettle();
    expect(
      jsonDecode(
        backend.singleRequest('POST', '/api/approvals/tasks/306/resolve').body,
      ),
      {'choice': 'apply'},
    );
    expect(
      find.byKey(const ValueKey('document-change-approval-306')),
      findsNothing,
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('dismiss-date-401')),
      400,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();
    backend.nextDateMutation = Completer<http.Response>();
    await tester.tap(find.byKey(const ValueKey('dismiss-date-401')));
    await tester.pump();
    expect(find.byKey(const ValueKey('date-approval-401')), findsOneWidget);
    expect(
      jsonDecode(
        backend.singleRequest('POST', '/api/intelligence/resolve').body,
      ),
      {
        'candidate_ids': [401],
        'decision': 'rejected',
      },
    );

    backend.nextDateMutation!.complete(_dateMutationResponse(401));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('date-approval-401')), findsNothing);
    expect(find.text('All caught up.'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('approvals-inbox-card')), findsNothing);
    expect(
      find.descendant(
        of: find.byType(SuchiPageHeader),
        matching: find.byType(CircleAvatar),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.compare_arrows), findsNothing);
    await _unmountShell(tester);
  });

  testWidgets('one failed section stays retryable and stale reviews reload', (
    tester,
  ) async {
    backend.failDates = true;
    await _pumpShell(tester, harness);
    await tester.tap(find.byKey(const ValueKey('approvals-inbox-card')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('document-change-approval-301')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.textContaining('Dates could not be loaded.'),
      400,
      scrollable: find.byType(Scrollable),
    );
    expect(find.textContaining('Dates could not be loaded.'), findsOneWidget);

    backend.failDates = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('date-approval-401')),
      400,
      scrollable: find.byType(Scrollable),
    );
    expect(find.byKey(const ValueKey('date-approval-401')), findsOneWidget);

    final readsBefore = backend.taskReads;
    backend.staleDocumentChangeOnce = true;
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('dismiss-document-change-301')),
      -400,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(find.byKey(const ValueKey('dismiss-document-change-301')));
    await tester.pumpAndSettle();

    expect(backend.taskReads, greaterThan(readsBefore));
    expect(
      find.byKey(const ValueKey('document-change-approval-301')),
      findsOneWidget,
    );
    await _unmountShell(tester);
  });

  test(
    'old-account reads, 401s, and mutations cannot affect a new account',
    () async {
      final controller = ApprovalsController(session: harness.services.session);
      addTearDown(controller.dispose);
      await controller.reload();
      String currentTitle() => controller.documentChanges
          .singleWhere((review) => review.id == 301)
          .documentTitle;
      expect(currentTitle(), 'Account 7 electricity bill');

      final oldMutationResponse = Completer<http.Response>();
      backend.nextDocumentChangeMutation = oldMutationResponse;
      final oldMutation = controller.resolveDocumentChange(
        301,
        ReviewDecision.accept,
      );
      await Future<void>.delayed(Duration.zero);

      expect(await harness.services.session.signOut(), isTrue);
      backend.userId = 8;
      await harness.services.session.pairWithToken(
        serverAddress: 'https://suchi.example.com',
        token: 'b' * 64,
      );
      await controller.reload();
      expect(currentTitle(), 'Account 8 electricity bill');

      oldMutationResponse.complete(_unauthorizedResponse());
      await oldMutation;
      expect(harness.services.session.state, SessionState.signedIn);
      expect(harness.services.session.user!.userId, 8);
      expect(currentTitle(), 'Account 8 electricity bill');

      final oldReadResponse = Completer<http.Response>();
      backend.nextTasksRead = oldReadResponse;
      final oldRead = controller.reload();
      await Future<void>.delayed(Duration.zero);

      expect(await harness.services.session.signOut(), isTrue);
      backend.userId = 9;
      await harness.services.session.pairWithToken(
        serverAddress: 'https://suchi.example.com',
        token: 'c' * 64,
      );
      await controller.reload();
      expect(currentTitle(), 'Account 9 electricity bill');

      oldReadResponse.complete(_unauthorizedResponse());
      await oldRead;
      expect(harness.services.session.state, SessionState.signedIn);
      expect(harness.services.session.user!.userId, 9);
      expect(currentTitle(), 'Account 9 electricity bill');
    },
  );
}

Future<void> _unmountShell(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

Future<void> _pumpShell(
  WidgetTester tester,
  MobileAppHarness harness, {
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: SuchiTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: ListenableBuilder(
        listenable: harness.services.session,
        builder: (context, _) =>
            harness.services.session.state == SessionState.signedIn
            ? SuchiShell(services: harness.services)
            : const Scaffold(body: Text('Signed out')),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}

final class _ReviewBackend {
  final requests = <http.Request>[];
  int userId = 7;
  int taskReads = 0;
  final pendingDocumentChangeIds = <int>{301, 302, 305, 306};
  bool datePending = true;
  bool failDates = false;
  bool staleDocumentChangeOnce = false;
  Completer<http.Response>? nextDocumentChangeMutation;
  Completer<http.Response>? nextDateMutation;
  Completer<http.Response>? nextTasksRead;

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    if (request.url.path == '/api/whoami') return _whoamiResponse(userId);
    if (request.method == 'GET' && request.url.path == '/api/tasks/') {
      taskReads++;
      final pending = nextTasksRead;
      if (pending != null) {
        nextTasksRead = null;
        return pending.future;
      }
      return _tasksResponse(
        userId,
        pendingDocumentChangeIds: pendingDocumentChangeIds,
      );
    }
    if (request.method == 'GET' && request.url.path == '/api/intelligence/') {
      if (failDates) {
        return http.Response(
          jsonEncode({'error': 'Dates are temporarily unavailable.'}),
          503,
          headers: {'content-type': 'application/json'},
        );
      }
      return _datesResponse(datePending: datePending);
    }
    if (request.method == 'POST' &&
        request.url.path.startsWith('/api/approvals/tasks/') &&
        request.url.path.endsWith('/resolve')) {
      final id = int.parse(request.url.pathSegments[3]);
      if (id == 301 && staleDocumentChangeOnce) {
        staleDocumentChangeOnce = false;
        return http.Response(
          jsonEncode({
            'code': 'stale_proposal',
            'error': 'The document suggestion changed.',
          }),
          409,
          headers: {'content-type': 'application/json'},
        );
      }
      final pending = nextDocumentChangeMutation;
      nextDocumentChangeMutation = null;
      final response = pending == null
          ? http.Response('', 204)
          : await pending.future;
      if (response.statusCode == 204) pendingDocumentChangeIds.remove(id);
      return response;
    }
    if (request.method == 'POST' &&
        request.url.path == '/api/intelligence/resolve') {
      final pending = nextDateMutation;
      final response = pending == null
          ? _dateMutationResponse(401)
          : await pending.future;
      if (response.statusCode == 200) datePending = false;
      return response;
    }
    return archiveResponse(request);
  }

  http.Request singleRequest(String method, String path) =>
      requests.singleWhere(
        (request) => request.method == method && request.url.path == path,
      );
}

http.Response _tasksResponse(
  int userId, {
  required Set<int> pendingDocumentChangeIds,
}) {
  final payload = jsonDecode(
    File('test/fixtures/api/v1/tasks-approvals.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final approvals = payload['approval_tasks']! as List<Object?>;
  for (final value in approvals) {
    final approval = value! as Map<String, Object?>;
    if (approval['id'] == 301) {
      approval['doc_title'] = 'Account $userId electricity bill';
    }
  }
  approvals.removeWhere((value) {
    final id = (value! as Map<String, Object?>)['id'];
    return const {301, 302, 305, 306}.contains(id) &&
        !pendingDocumentChangeIds.contains(id);
  });
  return http.Response(
    jsonEncode(payload),
    200,
    headers: {'content-type': 'application/json'},
  );
}

http.Response _datesResponse({required bool datePending}) {
  final payload = jsonDecode(
    File('test/fixtures/api/v1/intelligence-pending-dates.json')
        .readAsStringSync(),
  ) as Map<String, Object?>;
  if (!datePending) {
    payload['count'] = 0;
    payload['results'] = <Object?>[];
  }
  return http.Response(
    jsonEncode(payload),
    200,
    headers: {'content-type': 'application/json'},
  );
}

http.Response _whoamiResponse(int userId) => jsonResponse({
  'kind': 'token',
  'user_id': userId,
  'email': 'reviewer$userId@example.com',
  'display_name': 'Reviewer $userId',
  'instance_host': 'suchi.example.com',
  'role': 'admin',
  'authn_by': 'local-auth',
  'email_change_mode': 'password',
  'avatar_url': '/api/users/$userId/avatar',
  'system_id': 1,
  'system_name': 'Archive',
  'system_code': '',
  'capabilities': ['archive_intelligence'],
  'scopes': ['documents:read', 'documents:write'],
});

http.Response _dateMutationResponse(int id) => jsonResponse({
  'total': 1,
  'applied': 1,
  'results': [
    {'id': id, 'ok': true},
  ],
});

http.Response _unauthorizedResponse() => http.Response(
  jsonEncode({'error': 'Token expired.'}),
  401,
  headers: {'content-type': 'application/json'},
);
