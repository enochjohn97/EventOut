import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../models/client_event_model.dart';
import '../models/client_payment_model.dart';
import '../models/client_ticket_model.dart';
import '../services/client_api_service.dart';
import 'client_ui.dart';

/// Tapping a card in Events / Tickets / Payments opens one of these modals so
/// the organizer can read the full record without leaving the list.

Future<void> showClientEventDetails(
  BuildContext context,
  ClientEventModel event, {
  Future<void> Function()? onChanged,
}) {
  final image =
      event.absoluteImageUrl ??
      (event.imagePath != null && event.imagePath!.trim().isNotEmpty
          ? ApiClient().absoluteUrl(event.imagePath)
          : null);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _SheetBody(
      title: event.name,
      statusLabel: _titleCase(event.status),
      statusColor: clientStatusColor(event.status),
      imageUrl: image,
      rows: [
        ('Date', clientDate(event.eventDate)),
        ('Time', _timeLabel(event.eventTime)),
        ('Venue', event.address ?? event.state ?? 'Venue TBC'),
        ('Category', event.category ?? event.eventType ?? 'Not set'),
        ('Tickets sold', '${event.salesCount}'),
        (
          'Capacity',
          event.capacity == null ? 'Unlimited' : '${event.capacity}',
        ),
        ('Ticket price', clientEventPrice(event)),
        if ((event.tag ?? '').trim().isNotEmpty) ('Event tag', event.tag!),
        if ((event.customId ?? '').trim().isNotEmpty)
          ('Event ID', event.customId!),
      ],
      footer: event.isLive
          ? null
          : _EventPreviewActions(event: event, onChanged: onChanged),
    ),
  );
}

/// The preview modal's two actions: pay for the event, then publish it.
/// Publishing stays locked while the API reports the payment as outstanding.
class _EventPreviewActions extends StatefulWidget {
  final ClientEventModel event;
  final Future<void> Function()? onChanged;

  const _EventPreviewActions({required this.event, this.onChanged});

  @override
  State<_EventPreviewActions> createState() => _EventPreviewActionsState();
}

class _EventPreviewActionsState extends State<_EventPreviewActions> {
  bool _busy = false;

  Future<void> _makePayment() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final payment =
          await ClientApiService.initializeListingFeePayment(widget.event.id);
      final checkoutUrl = payment['authorization_url'].toString();
      final uri = Uri.parse(checkoutUrl);

      final opened = await launchUrl(
        uri,
        mode: LaunchMode.inAppBrowserView,
      );

      if (!mounted) return;
      if (!opened) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open the Paystack checkout page.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      await widget.onChanged?.call();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Checkout closed. Payment status refreshed; confirm payment before publishing.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publish() async {
    setState(() => _busy = true);
    try {
      await ClientApiService.publishEvent(widget.event.id);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      await widget.onChanged?.call();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Event published. It is now live.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final paymentOwed = widget.event.paymentOwed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _makePayment,
                icon: const Icon(Icons.credit_card, size: 16),
                label: const Text('Make payment'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _busy || paymentOwed ? null : _publish,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.brandRed,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppTheme.brandRed.withValues(
                    alpha: 0.35,
                  ),
                  disabledForegroundColor: Colors.white70,
                ),
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.rocket_launch_outlined, size: 16),
                label: const Text('Publish event'),
              ),
            ),
          ],
        ),
        if (paymentOwed) ...[
          const SizedBox(height: 8),
          const Text(
            'Publish unlocks once the event payment has been confirmed.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
          ),
        ],
      ],
    );
  }
}

Future<void> showClientTicketDetails(
  BuildContext context,
  ClientTicketModel ticket,
) {
  final paid = (ticket.paymentStatus ?? '').toLowerCase() == 'paid';
  final image = ticket.absoluteEventImage;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _SheetBody(
      title: ticket.eventName,
      subtitle: ticket.buyerName ?? 'Attendee',
      statusLabel: ticket.used ? 'Checked in' : _titleCase(ticket.status),
      statusColor: ticket.used
          ? const Color(0xFFB45309)
          : clientStatusColor(ticket.status),
      imageUrl: image,
      rows: [
        ('Ticket type', _tierName(ticket.ticketType)),
        (
          'Amount',
          ticket.priceDisplay?.isNotEmpty == true
              ? '₦${ticket.priceDisplay}'
              : clientMoney(ticket.amount),
        ),
        (
          'Payment',
          _titleCase(ticket.paymentStatus ?? (paid ? 'paid' : 'pending')),
        ),
        (
          'Purchased',
          clientDate(ticket.purchaseDate, fallback: 'Not recorded'),
        ),
        if ((ticket.barcode ?? '').trim().isNotEmpty)
          ('Ticket ID', ticket.barcode!),
        if ((ticket.reference ?? '').trim().isNotEmpty)
          ('Reference', ticket.reference!),
        if ((ticket.customId ?? '').trim().isNotEmpty)
          ('Record ID', ticket.customId!),
      ],
    ),
  );
}

Future<void> showClientPaymentDetails(
  BuildContext context,
  ClientPaymentModel payment,
) {
  final reference = payment.reference;
  Future<void> copy(BuildContext sheetContext) async {
    await Clipboard.setData(ClipboardData(text: reference));
    if (!sheetContext.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(sheetContext);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Reference $reference copied'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => _SheetBody(
      title: payment.eventName ?? 'Event payment',
      subtitle: payment.buyerName ?? 'Attendee',
      statusLabel: _titleCase(payment.status),
      statusColor: clientStatusColor(payment.status),
      imageUrl: payment.absoluteEventImage,
      rows: [
        ('Amount', clientMoney(payment.amount)),
        (
          'Tickets',
          '${payment.ticketCount} ticket${payment.ticketCount == 1 ? '' : 's'}',
        ),
        (
          'Paid on',
          payment.isPaid
              ? clientDate(
                  payment.paidAt ?? payment.createdAt,
                  fallback: 'Not recorded',
                )
              : clientDate(payment.createdAt, fallback: 'Not recorded'),
        ),
        if ((payment.eventDate ?? '').trim().isNotEmpty)
          ('Event date', clientDate(payment.eventDate)),
        if (reference.isNotEmpty) ('Reference', reference),
      ],
      footer: reference.isEmpty
          ? null
          : SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => copy(sheetContext),
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copy payment reference'),
              ),
            ),
    ),
  );
}

class _SheetBody extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String statusLabel;
  final Color statusColor;
  final String? imageUrl;
  final List<(String, String)> rows;
  final Widget? footer;

  const _SheetBody({
    required this.title,
    required this.statusLabel,
    required this.statusColor,
    required this.rows,
    this.subtitle,
    this.imageUrl,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.86;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (imageUrl != null && imageUrl!.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: CachedNetworkImage(
                  imageUrl: imageUrl!,
                  height: 150,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
              const SizedBox(height: 14),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ClientStatusChip(statusLabel, color: statusColor),
              ],
            ),
            if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFEDEFF3)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Column(
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0)
                      const Divider(height: 1, color: Color(0xFFEDEFF3)),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              rows[i].$1,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 3,
                            child: Text(
                              rows[i].$2,
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (footer != null) ...[const SizedBox(height: 16), footer!],
          ],
        ),
      ),
    );
  }
}

String _tierName(String value) =>
    value.toLowerCase() == 'vip' ? 'VIP' : _titleCase(value);

String _titleCase(String value) {
  if (value.isEmpty) return value;
  return value[0].toUpperCase() + value.substring(1);
}

String _timeLabel(String? raw) {
  if (raw == null || raw.trim().isEmpty) return 'Time TBC';
  final parts = raw.trim().split(':');
  final hour24 = int.tryParse(parts.first);
  if (hour24 == null || parts.length < 2) return raw.trim();
  final suffix = hour24 >= 12 ? 'PM' : 'AM';
  final hour = hour24 % 12 == 0 ? 12 : hour24 % 12;
  return '$hour:${parts[1]} $suffix';
}
