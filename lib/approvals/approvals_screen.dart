import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api_error.dart';
import '../api/api_models.dart';
import '../api/suchi_client.dart';
import '../auth/account_identity.dart';
import '../auth/session_controller.dart';
import '../theme/suchi_theme.dart';
import '../widgets/suchi_widgets.dart';
import 'approvals_controller.dart';

class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({
    required this.controller,
    required this.session,
    required this.identity,
    required this.client,
    required this.onOpenDocument,
    super.key,
  });

  final ApprovalsController controller;
  final SessionController session;
  final AccountIdentity identity;
  final SuchiClient client;
  final Future<void> Function(int documentId) onOpenDocument;

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  ModalRoute<void>? _route;
  NavigatorState? _navigator;
  bool _removingRoute = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_controllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_current(_generation)) unawaited(widget.controller.reload());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route ??= ModalRoute.of(context);
    _navigator ??= Navigator.of(context);
    _closeForIdentityChange();
  }

  @override
  void dispose() {
    _generation++;
    widget.controller.removeListener(_controllerChanged);
    super.dispose();
  }

  void _controllerChanged() {
    if (!mounted) return;
    if (_identityChanged) {
      _removeCapturedRoute();
      return;
    }
    setState(() {});
  }

  bool get _identityChanged =>
      widget.session.state != SessionState.signedIn ||
      widget.session.identity != widget.identity ||
      !identical(widget.session.client, widget.client);

  void _closeForIdentityChange() {
    if (_identityChanged) _removeCapturedRoute();
  }

  void _removeCapturedRoute() {
    if (_removingRoute) return;
    final route = _route;
    final navigator = _navigator;
    if (route == null || navigator == null || !route.isActive) return;
    _removingRoute = true;
    _generation++;
    navigator.removeRoute(route);
  }

  bool _current(int generation) =>
      mounted &&
      !_removingRoute &&
      generation == _generation &&
      !_identityChanged;

  Future<void> _resolveDocumentChange(
    DocumentChangeApprovalTask review,
    ReviewDecision decision,
  ) async {
    final generation = _generation;
    final fieldLabel = _fieldLabel(review.field);
    try {
      await widget.controller.resolveDocumentChange(review.id, decision);
      if (!_current(generation)) return;
      _showNotice(
        decision == ReviewDecision.accept
            ? review.field == DocumentChangeField.tag
                  ? 'Tag addition queued.'
                  : '$fieldLabel change queued.'
            : '$fieldLabel suggestion dismissed.',
      );
    } on ApiException catch (error) {
      if (!_current(generation)) return;
      _showNotice(
        friendlyApiMessage(
          error,
          fallback:
              'The ${fieldLabel.toLowerCase()} suggestion could not be updated.',
        ),
      );
    }
  }

  Future<void> _resolveDate(
    PendingDateReview review,
    ReviewDecision decision,
  ) async {
    final generation = _generation;
    try {
      await widget.controller.resolveDate(review.id, decision);
      if (!_current(generation)) return;
      _showNotice(
        decision == ReviewDecision.accept
            ? 'Date added to Calendar.'
            : 'Date suggestion dismissed.',
      );
    } on ApiException catch (error) {
      if (!_current(generation)) return;
      _showNotice(
        friendlyApiMessage(
          error,
          fallback: 'The date suggestion could not be updated.',
        ),
      );
    }
  }

  void _showNotice(String message) {
    if (!mounted || _identityChanged) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final showEmpty =
        !controller.loading &&
        controller.documentChangeError == null &&
        controller.dateError == null &&
        !controller.hasPending;
    return Scaffold(
      appBar: AppBar(title: const Text('Approvals')),
      body: RefreshIndicator(
        onRefresh: controller.reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            const SectionLabel('Document suggestions'),
            const SizedBox(height: 10),
            if (controller.documentChangeError case final error?) ...[
              InlineError(message: error, onRetry: controller.reload),
              const SizedBox(height: 14),
            ],
            if (controller.loadingDocumentChanges &&
                controller.documentChanges.isEmpty) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 14),
            ],
            for (final review in controller.documentChanges) ...[
              _documentChangeCard(review),
              const SizedBox(height: 12),
            ],
            if (controller.canReviewDates) ...[
              const SizedBox(height: 8),
              const SectionLabel('Dates'),
              const SizedBox(height: 10),
              if (controller.dateError case final error?) ...[
                InlineError(message: error, onRetry: controller.reload),
                const SizedBox(height: 14),
              ],
              if (controller.loadingDates && controller.dates.isEmpty) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 14),
              ],
              for (final review in controller.dates) ...[
                _dateCard(review),
                const SizedBox(height: 12),
              ],
            ],
            if (showEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 56),
                child: Center(child: Text('All caught up.')),
              ),
          ],
        ),
      ),
    );
  }

  Widget _documentChangeCard(DocumentChangeApprovalTask review) {
    final busy = widget.controller.documentChangeBusy(review.id);
    final current = switch (review.field) {
      DocumentChangeField.title =>
        review.currentValue.isEmpty ? 'Untitled' : review.currentValue,
      DocumentChangeField.category =>
        review.currentValue.isEmpty ? 'Unfiled' : review.currentValue,
      DocumentChangeField.tag =>
        review.currentValue.isEmpty ? 'No existing tags' : review.currentValue,
    };
    final proposed = review.field == DocumentChangeField.tag
        ? 'Add tag: ${review.proposedValue}'
        : review.proposedValue;
    return SuchiCard(
      key: ValueKey('document-change-approval-${review.id}'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _documentLink(review.documentId, review.documentTitle),
          const SizedBox(height: 12),
          SectionLabel(_fieldLabel(review.field)),
          const SizedBox(height: 6),
          _changeValues(current, proposed),
          const SizedBox(height: 10),
          _score(review.score),
          _details(
            key: ValueKey('document-change-details-${review.id}'),
            children: [
              if (review.source != null)
                _detailSummary(
                  'Why this was suggested',
                  _sourceLabel(review.source!),
                ),
              if (review.deadlineAt != null)
                _detailLine('Deadline', _deadline(review.deadlineAt!)),
              if (!review.sourceCurrent || review.reviewConflict)
                _detailLine('Status', 'Document changed'),
              if (review.evidenceSources.isNotEmpty)
                _detailGroup('Similar documents', review.evidenceSources),
            ],
          ),
          _actions(
            busy: busy,
            dismissKey: ValueKey('dismiss-document-change-${review.id}'),
            acceptKey: ValueKey('accept-document-change-${review.id}'),
            onDismiss: () =>
                _resolveDocumentChange(review, ReviewDecision.dismiss),
            onAccept: () =>
                _resolveDocumentChange(review, ReviewDecision.accept),
          ),
        ],
      ),
    );
  }

  Widget _dateCard(PendingDateReview review) {
    final busy = widget.controller.dateBusy(review.id);
    return SuchiCard(
      key: ValueKey('date-approval-${review.id}'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _documentLink(review.documentId, review.documentTitle),
          const SizedBox(height: 4),
          Text(
            _roleLabel(review.role),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          _changeValues('Not in Calendar', _dateLabel(review)),
          const SizedBox(height: 10),
          _score(review.score),
          _details(
            key: ValueKey('date-details-${review.id}'),
            children: [
              _detailSummary('Why this was suggested', review.extractor),
              if (review.rawText.isNotEmpty)
                _detailLine('Detected text', review.rawText, maxLines: 3),
              if (review.evidenceText.isNotEmpty)
                _detailGroup('Why this was suggested', [review.evidenceText]),
            ],
          ),
          _actions(
            busy: busy,
            dismissKey: ValueKey('dismiss-date-${review.id}'),
            acceptKey: ValueKey('accept-date-${review.id}'),
            onDismiss: () => _resolveDate(review, ReviewDecision.dismiss),
            onAccept: () => _resolveDate(review, ReviewDecision.accept),
          ),
        ],
      ),
    );
  }

  Widget _documentLink(int documentId, String title) {
    final colors = SuchiColors.of(context);
    return InkWell(
      key: ValueKey('open-approval-document-$documentId'),
      borderRadius: BorderRadius.circular(8),
      onTap: () => widget.onOpenDocument(documentId),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.open_in_new, size: 19, color: colors.accent),
          ],
        ),
      ),
    );
  }

  Widget _changeValues(String current, String proposed) {
    final colors = SuchiColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          child: Text(current, style: TextStyle(color: colors.muted)),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text('→'),
        ),
        Flexible(
          child: Text(
            proposed,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _score(double score) => Align(
    alignment: Alignment.centerLeft,
    child: QuietBadge('Score ${(score * 100).round()}%'),
  );

  Widget _details({required Key key, required List<Widget> children}) => Theme(
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: ExpansionTile(
      key: key,
      initiallyExpanded: false,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      title: const Text('Details'),
      children: children,
    ),
  );

  Widget _detailLine(String label, String value, {int maxLines = 1}) {
    final colors = SuchiColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: SuchiTheme.monoLabel.copyWith(color: colors.muted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailSummary(String label, String value) {
    final colors = SuchiColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: SuchiTheme.monoLabel.copyWith(color: colors.muted),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(child: Text(value, textAlign: TextAlign.end)),
        ],
      ),
    );
  }

  Widget _detailGroup(String label, List<String> values) {
    final colors = SuchiColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: SuchiTheme.monoLabel.copyWith(color: colors.muted),
          ),
          const SizedBox(height: 6),
          for (final value in values)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• $value',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  Widget _actions({
    required bool busy,
    required Key dismissKey,
    required Key acceptKey,
    required VoidCallback onDismiss,
    required VoidCallback onAccept,
  }) => Row(
    children: [
      Expanded(
        child: OutlinedButton(
          key: dismissKey,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: busy ? null : onDismiss,
          child: const Text('Dismiss'),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: FilledButton(
          key: acceptKey,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: busy ? null : onAccept,
          child: busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Accept'),
        ),
      ),
    ],
  );

  String _dateLabel(PendingDateReview review) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    return switch (review.precision) {
      'year' => DateFormat.y(locale).format(review.date),
      'month' => DateFormat.yMMMM(locale).format(review.date),
      _ => DateFormat.yMMMMd(locale).format(review.date),
    };
  }

  String _deadline(int seconds) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final value = DateTime.fromMillisecondsSinceEpoch(
      seconds * Duration.millisecondsPerSecond,
      isUtc: true,
    ).toLocal();
    return DateFormat.yMMMd(locale).format(value);
  }

  static String _roleLabel(String role) => switch (role) {
    'issued' => 'Issued date',
    'due' => 'Due date',
    'start' => 'Start date',
    'end' => 'End date',
    'expiry' => 'Expiry date',
    'renewal' => 'Renewal date',
    'service' => 'Service date',
    _ => 'Other date',
  };

  static String _fieldLabel(DocumentChangeField field) => switch (field) {
    DocumentChangeField.title => 'Title',
    DocumentChangeField.category => 'Category',
    DocumentChangeField.tag => 'Tag',
  };

  static String _sourceLabel(String source) => switch (source) {
    'llm' => 'Model suggestion',
    'archive' => 'Archive match',
    'language-detector' => 'Language detector',
    _ => source,
  };
}
