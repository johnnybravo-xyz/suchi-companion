import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api_error.dart';
import '../api/api_models.dart';
import '../api/suchi_client.dart';
import '../auth/account_identity.dart';
import '../auth/session_controller.dart';
import '../theme/suchi_theme.dart';
import '../widgets/adaptive_layout.dart';
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

  Future<void> _resolveApproval(ApprovalTask review, String choice) async {
    final generation = _generation;
    final change = review.documentChange;
    try {
      await widget.controller.resolveApproval(review.id, choice);
      if (!_current(generation)) return;
      final fieldLabel = change == null ? null : _fieldLabel(change);
      _showNotice(switch (choice) {
        'apply' when change?.field == DocumentChangeField.tag =>
          'Tag addition queued.',
        'apply' when fieldLabel != null => '$fieldLabel change queued.',
        'reject' || 'dismiss' => 'Approval dismissed.',
        _ => 'Approval decision queued.',
      });
    } on ApiException catch (error) {
      if (!_current(generation)) return;
      _showNotice(
        friendlyApiMessage(
          error,
          fallback: 'The approval could not be updated.',
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
        controller.approvalError == null &&
        controller.dateError == null &&
        !controller.hasPending;
    return Scaffold(
      appBar: AppBar(title: const Text('Approvals')),
      body: AdaptiveCenteredContent(
        child: RefreshIndicator(
          onRefresh: controller.reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              const SectionLabel('Approvals'),
              const SizedBox(height: 10),
              if (controller.approvalError case final error?) ...[
                InlineError(message: error, onRetry: controller.reload),
                const SizedBox(height: 14),
              ],
              if (controller.loadingApprovals &&
                  controller.approvals.isEmpty) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 14),
              ],
              for (final review in controller.approvals) ...[
                _approvalCard(review),
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
      ),
    );
  }

  Widget _approvalCard(ApprovalTask review) {
    final change = review.documentChange;
    final busy = widget.controller.approvalBusy(review.id);
    final key = change == null
        ? ValueKey('approval-${review.id}')
        : ValueKey('document-change-approval-${review.id}');
    return SuchiCard(
      key: key,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (review.documentId case final documentId?) ...[
            _documentLink(documentId, review.documentTitle!),
            const SizedBox(height: 12),
          ],
          SectionLabel(
            change == null ? _workflowLabel(review) : _fieldLabel(change),
          ),
          const SizedBox(height: 6),
          if (change == null)
            Text(review.prompt)
          else ...[
            _changeValues(_currentValue(change), _proposedValue(change)),
            const SizedBox(height: 10),
            _score(change.score),
          ],
          const SizedBox(height: 10),
          _details(
            key: ValueKey(
              change == null
                  ? 'approval-details-${review.id}'
                  : 'document-change-details-${review.id}',
            ),
            children: [
              if (change?.source case final source?)
                _detailSummary('Why this was suggested', _sourceLabel(source)),
              if (review.deadlineAt case final deadline?)
                _detailLine('Deadline', _deadline(deadline)),
              if (change != null &&
                  (!change.sourceCurrent || change.reviewConflict))
                _detailLine('Status', 'Document changed'),
              if (change != null && change.evidenceSources.isNotEmpty)
                _detailGroup('Similar documents', change.evidenceSources),
              if (change == null) _detailLine('Workflow', review.approvalName),
            ],
          ),
          _approvalActions(review, busy: busy),
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

  Widget _approvalActions(ApprovalTask review, {required bool busy}) {
    if (review.documentChange != null &&
        review.choices.length == 2 &&
        review.choices.contains('apply') &&
        review.choices.contains('reject')) {
      return _actions(
        busy: busy,
        dismissKey: ValueKey('dismiss-document-change-${review.id}'),
        acceptKey: ValueKey('accept-document-change-${review.id}'),
        onDismiss: () => _resolveApproval(review, 'reject'),
        onAccept: () => _resolveApproval(review, 'apply'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < review.choices.length; index++) ...[
          if (index > 0) const SizedBox(height: 8),
          if (index == 0)
            FilledButton(
              key: ValueKey('approval-${review.id}-${review.choices[index]}'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: busy
                  ? null
                  : () => _resolveApproval(review, review.choices[index]),
              child: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_choiceLabel(review.choices[index])),
            )
          else
            OutlinedButton(
              key: ValueKey('approval-${review.id}-${review.choices[index]}'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: busy
                  ? null
                  : () => _resolveApproval(review, review.choices[index]),
              child: Text(_choiceLabel(review.choices[index])),
            ),
        ],
      ],
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

  static String _fieldLabel(DocumentChangeApproval change) =>
      switch (change.field) {
        DocumentChangeField.title => 'Title',
        DocumentChangeField.category => 'Category',
        DocumentChangeField.correspondent => 'Correspondent',
        DocumentChangeField.tag => 'Tag',
        DocumentChangeField.language => 'Language',
        DocumentChangeField.customField => change.fieldName!,
      };

  static String _currentValue(DocumentChangeApproval change) {
    if (change.currentValue.isNotEmpty) return change.currentValue;
    return switch (change.field) {
      DocumentChangeField.title => 'Untitled',
      DocumentChangeField.category => 'Unfiled',
      DocumentChangeField.correspondent => 'No correspondent',
      DocumentChangeField.tag => 'No existing tags',
      DocumentChangeField.language => 'No language',
      DocumentChangeField.customField => 'Not set',
    };
  }

  static String _proposedValue(DocumentChangeApproval change) =>
      change.field == DocumentChangeField.tag
      ? 'Add tag: ${change.proposedValue}'
      : change.proposedValue;

  static String _workflowLabel(ApprovalTask review) =>
      review.approvalName == 'rescan-proposal'
      ? 'Pipeline rescan'
      : 'Workflow approval';

  static String _choiceLabel(String choice) => switch (choice) {
    'apply' => 'Accept',
    'reject' => 'Reject',
    'approve' => 'Approve',
    'approve_all' || 'rescan_all' => 'Rescan all',
    'approve_sample' || 'try_20' => 'Try 20 first',
    'dismiss' => 'Dismiss',
    _ => choice.replaceAll('-', ' ').replaceAll('_', ' '),
  };
  static String _sourceLabel(String source) => switch (source) {
    'llm' => 'Model suggestion',
    'archive' => 'Archive match',
    'language-detector' => 'Language detector',
    _ => source,
  };
}
