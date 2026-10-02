import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api_error.dart';
import '../api/api_models.dart';
import '../api/suchi_client.dart';
import '../documents/document_list_mode.dart';
import '../documents/thumbnail_cache.dart';
import '../theme/suchi_theme.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: 'Suchi Companion',
    child: CustomPaint(
      size: Size.square(size),
      painter: const _BrandMarkPainter(),
    ),
  );
}

final class _BrandMarkPainter extends CustomPainter {
  const _BrandMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 64;
    canvas.scale(scale, scale);
    final border = Paint()
      ..color = SuchiColors.light.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(8, 8, 48, 48),
        const Radius.circular(8),
      ),
      Paint()..color = SuchiColors.light.manila,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(8, 8, 48, 48),
        const Radius.circular(8),
      ),
      border,
    );
    final line = Paint()
      ..color = SuchiColors.light.ink
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    for (final y in const [19.0, 28.0, 46.0]) {
      canvas.drawCircle(
        Offset(17.5, y),
        2.2,
        Paint()..color = SuchiColors.light.ink,
      );
      canvas.drawLine(Offset(23, y), Offset(48, y), line);
    }
    canvas.drawCircle(
      const Offset(16.8, 37.25),
      3.2,
      Paint()..color = SuchiColors.light.accent,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(22.5, 33.5, 29.5, 7.5),
        const Radius.circular(3.75),
      ),
      Paint()..color = SuchiColors.light.accent,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class SuchiCard extends StatelessWidget {
  const SuchiCard({
    required this.child,
    super.key,
    this.padding,
    this.color,
    this.elevated = true,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final colors = SuchiColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? colors.surface,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: colors.line),
        boxShadow: elevated
            ? const [
                BoxShadow(
                  color: Color(0x0A17181A),
                  blurRadius: 18,
                  offset: Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(17),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = SuchiColors.of(context);
    return Text(
      text.toUpperCase(),
      style: SuchiTheme.monoLabel.copyWith(color: color ?? colors.muted),
    );
  }
}

class JdChip extends StatelessWidget {
  const JdChip({required this.code, super.key});

  final int? code;

  @override
  Widget build(BuildContext context) {
    final colors = SuchiColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.tint,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        child: Text(
          code?.toString() ?? '—',
          style: SuchiTheme.monoLabel.copyWith(color: colors.accent),
        ),
      ),
    );
  }
}

class QuietBadge extends StatelessWidget {
  const QuietBadge(this.label, {super.key, this.foreground, this.background});

  final String label;
  final Color? foreground;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final colors = SuchiColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background ?? colors.tint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        child: Text(
          label.toUpperCase(),
          style: SuchiTheme.monoLabel.copyWith(
            color: foreground ?? colors.accent,
          ),
        ),
      ),
    );
  }
}

class SuchiPageHeader extends StatelessWidget {
  const SuchiPageHeader({
    required this.serverLabel,
    required this.userLabel,
    super.key,
  });

  final String serverLabel;
  final String userLabel;

  @override
  Widget build(BuildContext context) {
    final colors = SuchiColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
      child: Row(
        children: [
          const BrandMark(size: 26),
          const SizedBox(width: 9),
          const Expanded(
            child: Text(
              'suchi',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(width: 12),
          _accountAvatar(colors),
        ],
      ),
    );
  }

  Widget _accountAvatar(SuchiColors colors) => Semantics(
    label: 'Signed in as $userLabel on $serverLabel',
    excludeSemantics: true,
    child: CircleAvatar(
      radius: 15,
      backgroundColor: colors.manila,
      foregroundColor: colors.ink,
      child: Text(
        initialsFor(userLabel),
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
      ),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.title,
    required this.message,
    super.key,
    this.icon = Icons.description_outlined,
    this.action,
  });

  final String title;
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = SuchiColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: colors.muted),
            const SizedBox(height: 14),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class InlineError extends StatelessWidget {
  const InlineError({
    required this.message,
    super.key,
    this.requestId,
    this.onRetry,
  });

  final String message;
  final String? requestId;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = SuchiColors.of(context);
    return Semantics(
      liveRegion: true,
      child: SuchiCard(
        color: colors.danger.withValues(
          alpha: Theme.of(context).brightness == Brightness.dark ? 0.13 : 0.10,
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: colors.danger),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message, style: Theme.of(context).textTheme.bodyMedium),
                  if (requestId != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Request $requestId',
                      style: SuchiTheme.monoLabel.copyWith(color: colors.muted),
                    ),
                  ],
                ],
              ),
            ),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class DocumentThumb extends StatefulWidget {
  const DocumentThumb({
    required this.client,
    required this.cache,
    required this.documentId,
    required this.sensitive,
    super.key,
    this.width = 48,
    this.height = 56,
    this.reveal = false,
    this.onUnauthorized,
  });

  final SuchiClient? client;
  final ThumbnailMemoryCache cache;
  final int documentId;
  final bool sensitive;
  final double width;
  final double height;
  final bool reveal;
  final void Function(ApiException error)? onUnauthorized;

  @override
  State<DocumentThumb> createState() => _DocumentThumbState();
}

class _DocumentThumbState extends State<DocumentThumb> {
  Future<ThumbnailResult>? _result;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant DocumentThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.documentId != widget.documentId ||
        oldWidget.reveal != widget.reveal ||
        oldWidget.sensitive != widget.sensitive ||
        oldWidget.client != widget.client) {
      _load();
    }
  }

  void _load() {
    final client = widget.client;
    if (client == null || widget.sensitive && !widget.reveal) {
      _result = null;
      return;
    }
    _result = widget.cache
        .load(client, widget.documentId, width: 160, reveal: widget.reveal)
        .onError((error, _) {
          final failure =
              error ?? StateError('Thumbnail request failed without an error.');
          if (failure case final ApiException api when api.expiresSession) {
            widget.onUnauthorized?.call(api);
          }
          throw failure;
        });
  }

  @override
  Widget build(BuildContext context) {
    final colors = SuchiColors.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: ColoredBox(
          color: colors.manila,
          child: widget.client == null
              ? Center(
                  child: Icon(
                    Icons.offline_pin_outlined,
                    size: 22,
                    color: colors.muted,
                  ),
                )
              : widget.sensitive && !widget.reveal
              ? const _SensitivePlaceholder()
              : FutureBuilder<ThumbnailResult>(
                  future: _result,
                  builder: (context, snapshot) {
                    if (snapshot.data case final ThumbnailImage image) {
                      return Image.memory(
                        image.bytes,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        excludeFromSemantics: true,
                      );
                    }
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }
                    return Center(
                      child: Icon(
                        Icons.description_outlined,
                        size: 22,
                        color: colors.muted,
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class IndexRow extends StatelessWidget {
  const IndexRow({
    required this.document,
    required this.client,
    required this.cache,
    required this.onTap,
    required this.mode,
    super.key,
    this.enabled = true,
    this.onUnauthorized,
  });

  final DocumentSummary document;
  final SuchiClient? client;
  final ThumbnailMemoryCache cache;
  final VoidCallback onTap;
  final DocumentListMode mode;
  final bool enabled;
  final void Function(ApiException error)? onUnauthorized;

  @override
  Widget build(BuildContext context) {
    final colors = SuchiColors.of(context);
    final compact = mode == DocumentListMode.compact;
    final detailed = mode == DocumentListMode.detailed;
    final metadata = detailed
        ? _detailedMetadata(document)
        : [
            document.isSensitive
                ? '${sensitivityLabel(document.sensitivity)} · preview hidden'
                : documentMeta(document),
          ];
    final tags = detailed && !document.isSensitive
        ? _detailedTags(document)
        : const <String>[];
    final classification = switch (document.sensitivity) {
      'public' => 'Public',
      'internal' => 'Internal',
      'confidential' => 'Confidential',
      'restricted' => 'Restricted',
      _ => 'Not set',
    };
    return Semantics(
      button: true,
      enabled: enabled,
      excludeSemantics: true,
      onTap: enabled ? onTap : null,
      label: [
        document.title,
        'category ${document.jdCategoryCode ?? 'unfiled'}',
        if (document.jdCategoryName case final name?
            when name.trim().isNotEmpty)
          name,
        classification,
        ...metadata,
        ...tags,
      ].join(', '),
      child: InkWell(
        onTap: enabled ? onTap : null,
        excludeFromSemantics: true,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: detailed ? 118 : (compact ? 66 : 78),
          ),
          child: Padding(
            padding: detailed
                ? const EdgeInsets.all(14)
                : EdgeInsets.symmetric(
                    horizontal: compact ? 10 : 12,
                    vertical: compact ? 8 : 10,
                  ),
            child: Row(
              crossAxisAlignment: detailed
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                if (mode == DocumentListMode.standard || !enabled) ...[
                  enabled
                      ? SizedBox.square(
                          dimension: 10,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        )
                      : SizedBox.square(
                          dimension: mode == DocumentListMode.standard
                              ? 10
                              : 16,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        ),
                  const SizedBox(width: 10),
                ],
                DocumentThumb(
                  key: ValueKey(document.id),
                  client: client,
                  cache: cache,
                  documentId: document.id,
                  sensitive: document.isSensitive,
                  width: detailed ? 72 : (compact ? 38 : 48),
                  height: detailed ? 88 : (compact ? 44 : 56),
                  onUnauthorized: onUnauthorized,
                ),
                SizedBox(width: detailed ? 12 : (compact ? 10 : 11)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (detailed)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _title(context)),
                            const SizedBox(width: 8),
                            JdChip(code: document.jdCategoryCode),
                          ],
                        )
                      else
                        _title(context),
                      const SizedBox(height: 4),
                      for (final line in metadata)
                        Text(
                          line,
                          maxLines: detailed ? null : 1,
                          overflow: detailed ? null : TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                fontSize: compact || detailed ? 11.5 : 10.5,
                              ),
                        ),
                      if (tags.isNotEmpty) ...[
                        const SizedBox(height: 7),
                        Wrap(
                          spacing: 5,
                          runSpacing: 5,
                          children: [
                            for (final tag in tags)
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: colors.manila,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 3,
                                  ),
                                  child: Text(
                                    tag,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: colors.ink,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (!detailed) ...[
                  const SizedBox(width: 8),
                  JdChip(code: document.jdCategoryCode),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _title(BuildContext context) => Text(
    document.title,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: Theme.of(context).textTheme.titleMedium?.copyWith(
      fontSize: switch (mode) {
        DocumentListMode.standard => 13.5,
        DocumentListMode.compact => 14,
        DocumentListMode.detailed => 15,
      },
      fontWeight: mode == DocumentListMode.standard ? null : FontWeight.w600,
    ),
  );
}

List<String> _detailedMetadata(DocumentSummary document) {
  final category = [
    if (document.jdAreaName case final area? when area.trim().isNotEmpty) area,
    if (document.jdCategoryName case final name? when name.trim().isNotEmpty)
      name,
  ].join(' · ');
  final correspondents = document.correspondents
      .where((name) => name.trim().isNotEmpty)
      .take(2)
      .join(', ');
  return [
    if (category.isNotEmpty) category,
    DateFormat.yMMMd().format(
      DateTime.fromMillisecondsSinceEpoch(
        document.createdAt * 1000,
        isUtc: true,
      ).toLocal(),
    ),
    if (document.isSensitive)
      '${sensitivityLabel(document.sensitivity)} · preview hidden'
    else if (correspondents.isNotEmpty)
      correspondents,
  ];
}

List<String> _detailedTags(DocumentSummary document) => [
  ...document.tags.take(3),
  if (document.tags.length > 3) '+${document.tags.length - 3}',
];

class ListSkeleton extends StatelessWidget {
  const ListSkeleton({
    super.key,
    this.rows = 5,
    this.mode = DocumentListMode.standard,
  });

  final int rows;
  final DocumentListMode mode;

  @override
  Widget build(BuildContext context) {
    final colors = SuchiColors.of(context);
    if (mode != DocumentListMode.standard) {
      final compact = mode == DocumentListMode.compact;
      return Column(
        children: [
          for (var index = 0; index < rows; index++) ...[
            if (index > 0) SizedBox(height: compact ? 6 : 10),
            SuchiCard(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: compact ? 66 : 118),
                child: Padding(
                  padding: compact
                      ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
                      : const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: compact ? 38 : 72,
                        height: compact ? 44 : 88,
                        decoration: BoxDecoration(
                          color: colors.manila,
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                      SizedBox(width: compact ? 10 : 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 10,
                              width: 170,
                              color: colors.surface2,
                            ),
                            const SizedBox(height: 9),
                            Container(
                              height: 8,
                              width: 110,
                              color: colors.surface2,
                            ),
                            if (!compact) ...[
                              const SizedBox(height: 9),
                              Container(
                                height: 8,
                                width: 140,
                                color: colors.surface2,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      );
    }
    return SuchiCard(
      child: Column(
        children: List.generate(
          rows,
          (index) => Container(
            height: 78,
            decoration: BoxDecoration(
              border: index == rows - 1
                  ? null
                  : Border(bottom: BorderSide(color: colors.line)),
            ),
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 46,
                  decoration: BoxDecoration(
                    color: colors.manila,
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(height: 10, width: 170, color: colors.surface2),
                      const SizedBox(height: 9),
                      Container(height: 8, width: 110, color: colors.surface2),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String initialsFor(String value) {
  final words = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty);
  final letters = words
      .take(2)
      .map((word) => word.characters.first.toUpperCase())
      .join();
  return letters.isEmpty ? 'S' : letters;
}

String documentMeta(DocumentSummary document) {
  final pieces = <String>[
    ?document.jdCategoryName,
    if (document.correspondents.isNotEmpty) document.correspondents.first,
    DateFormat.yMMMd().format(
      DateTime.fromMillisecondsSinceEpoch(
        document.createdAt * 1000,
        isUtc: true,
      ).toLocal(),
    ),
  ];
  return pieces.join(' · ');
}

String sensitivityLabel(String value) => switch (value) {
  'restricted' => 'Restricted',
  'confidential' => 'Confidential',
  _ => 'Sensitive',
};

String friendlyApiMessage(ApiException error, {required String fallback}) {
  if (error.statusCode == 403) return 'Your token does not permit this action.';
  if (error.statusCode == 404) return 'This document is no longer available.';
  if (error.statusCode == 423) {
    return 'This document is locked and cannot be changed.';
  }
  if (error.kind == ApiFailureKind.network ||
      error.kind == ApiFailureKind.timeout) {
    return 'Suchi could not be reached. Check your connection and try again.';
  }
  if (error.kind == ApiFailureKind.server) {
    return 'The Suchi server is temporarily unavailable.';
  }
  return fallback;
}

class _SensitivePlaceholder extends StatelessWidget {
  const _SensitivePlaceholder();

  @override
  Widget build(BuildContext context) {
    final colors = SuchiColors.of(context);
    return Semantics(
      label: 'Sensitive preview hidden',
      child: Center(
        child: Icon(Icons.lock_outline, size: 21, color: colors.ink),
      ),
    );
  }
}
