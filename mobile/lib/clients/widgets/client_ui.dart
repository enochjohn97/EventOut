import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../models/client_event_model.dart';

String clientMoney(num value) {
  final format = NumberFormat.currency(
    symbol: '₦',
    decimalDigits: value % 1 == 0 ? 0 : 2,
  );
  return format.format(value);
}

String clientNumber(num value) => NumberFormat.decimalPattern().format(value);

/// Price exactly as the web Events table prints it: only the tiers the
/// organizer enabled, so a tiered event never shows "Free" just because the
/// legacy `price` column is zero. One tier → that amount, several → a range.
String clientEventPrice(ClientEventModel event) {
  final modes = (event.ticketTypeMode ?? 'all')
      .split(',')
      .map((mode) => mode.trim().toLowerCase())
      .where((mode) => mode.isNotEmpty)
      .toList();
  final explicitTiers = modes.isNotEmpty && !modes.contains('all');

  final prices = <double>[];
  void include(String tier, double value) {
    if (value <= 0) return;
    if (explicitTiers && !modes.contains(tier)) return;
    prices.add(value);
  }

  include('regular', event.regularPrice);
  include('vip', event.vipPrice);
  include('premium', event.premiumPrice);
  if (prices.isEmpty && event.price > 0) prices.add(event.price);
  if (prices.isEmpty) return 'Free';

  prices.sort();
  if (prices.length == 1) return clientMoney(prices.first);
  return '${clientMoney(prices.first)} – ${clientMoney(prices.last)}';
}

String clientDate(String? raw, {String fallback = 'Date TBC'}) {
  if (raw == null || raw.trim().isEmpty) return fallback;
  final value = raw.trim().replaceFirst(' ', 'T');
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return raw.trim();
  return DateFormat('MMM d, yyyy').format(parsed);
}

String clientDateTime(String? raw) {
  if (raw == null || raw.trim().isEmpty) return 'Date TBC';
  final parsed = DateTime.tryParse(raw.trim().replaceFirst(' ', 'T'));
  if (parsed == null) return raw.trim();
  return DateFormat('MMM d, yyyy · h:mm a').format(parsed);
}

class ClientSectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const ClientSectionHeader(
    this.title, {
    super.key,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
          ),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              child: Text(
                actionLabel!,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}

/// Organizer avatar shared by the home app bar and the profile header.
///
/// The API returns `profile_pic` as a root-relative path such as
/// `/uploads/profiles/profile_12_....jpg`, so it must be resolved against the
/// API origin before Flutter can load it. Falls back to initials when there is
/// no picture or the image cannot be fetched.
class ClientAvatar extends StatelessWidget {
  final String? imagePath;
  final String initials;
  final double radius;

  const ClientAvatar({
    super.key,
    required this.imagePath,
    required this.initials,
    this.radius = 18,
  });

  @override
  Widget build(BuildContext context) {
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: AppTheme.brandRed.withValues(alpha: 0.12),
      child: Text(
        initials,
        style: TextStyle(
          fontSize: radius * 0.68,
          fontWeight: FontWeight.w800,
          color: AppTheme.brandRed,
        ),
      ),
    );

    final url = ApiClient().absoluteUrl(imagePath);
    if (url.isEmpty) return fallback;

    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        httpHeaders: ApiClient().imageHeadersFor(url),
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        placeholder: (_, _) => fallback,
        errorWidget: (_, _, _) => fallback,
      ),
    );
  }
}

class ClientStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color accent;

  const ClientStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.accent = AppTheme.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDEFF3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: accent),
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }
}

class ClientStatusChip extends StatelessWidget {
  final String label;
  final Color? color;

  const ClientStatusChip(this.label, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final tone = color ?? AppTheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: tone,
        ),
      ),
    );
  }
}

Color clientStatusColor(String status) {
  switch (status.toLowerCase()) {
    case 'published':
    case 'paid':
    case 'valid':
    case 'approved':
    case 'verified':
      return AppTheme.success;
    case 'pending':
    case 'scheduled':
    case 'draft':
      return const Color(0xFFB45309);
    case 'failed':
    case 'cancelled':
    case 'invalid':
    case 'rejected':
      return AppTheme.error;
    default:
      return AppTheme.textMuted;
  }
}

class ClientEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const ClientEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 30, color: AppTheme.primary),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

/// Small helper for the "3 days ago"-style secondary line on records.
String clientRelativeDay(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '';
  final parsed = DateTime.tryParse(raw.trim().replaceFirst(' ', 'T'));
  if (parsed == null) return '';
  final days = DateTime.now().difference(parsed).inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 30) return '$days days ago';
  return DateFormat('MMM d, yyyy').format(parsed);
}
