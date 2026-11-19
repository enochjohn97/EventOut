import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../models/client_ticket_model.dart';
import '../providers/client_auth_provider.dart';
import '../providers/client_data_provider.dart';
import '../widgets/client_detail_sheets.dart';
import '../widgets/client_ui.dart';

class ClientTicketsScreen extends StatelessWidget {
  const ClientTicketsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<ClientAuthProvider>();

    final data = context.watch<ClientDataProvider>();
    final clientId = auth.client?.profileId;
    final tickets = data.tickets;
    final used = tickets.where((t) => t.used).length;
    final valid = tickets
        .where((t) => !t.used && t.status.toLowerCase() == 'valid')
        .length;
    // Same numbers the web Tickets page shows: the API counts every sold
    // ticket and splits each payment across the tickets it paid for.
    final sold = data.ticketStats.totalTickets;
    final revenue = data.ticketStats.totalRevenue;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Tickets'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (clientId != null) await data.refresh(clientId);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            Row(
              children: [
                Expanded(
                  child: _summary('Sold', clientNumber(sold), AppTheme.primary),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _summary(
                    'Valid',
                    clientNumber(valid),
                    AppTheme.success,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _summary(
                    'Checked in',
                    clientNumber(used),
                    const Color(0xFFB45309),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.brandRed.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.receipt_long_outlined,
                    size: 18,
                    color: AppTheme.brandRed,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Paid ticket revenue',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    clientMoney(revenue),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.brandRed,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (data.isLoading && tickets.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (tickets.isEmpty)
              const ClientEmptyState(
                icon: Icons.confirmation_number_outlined,
                title: 'No tickets sold yet',
                message:
                    'Tickets purchased for your events will appear here in real time.',
              )
            else
              ...tickets.map((ticket) => _ticketCard(context, ticket)),
          ],
        ),
      ),
    );
  }

  Widget _summary(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEDEFF3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _ticketCard(BuildContext context, ClientTicketModel ticket) {
    final paid = (ticket.paymentStatus ?? '').toLowerCase() == 'paid';
    final color = ticket.used
        ? const Color(0xFFB45309)
        : clientStatusColor(ticket.status);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFEDEFF3)),
        ),
        child: InkWell(
          onTap: () => showClientTicketDetails(context, ticket),
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        ticket.eventName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    ClientStatusChip(
                      ticket.used ? 'Checked in' : _titleCase(ticket.status),
                      color: color,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(
                      Icons.person_outline,
                      size: 14,
                      color: AppTheme.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        ticket.buyerName ?? 'Attendee',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      ticket.priceDisplay?.isNotEmpty == true
                          ? '₦${ticket.priceDisplay}'
                          : clientMoney(ticket.amount),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    ClientStatusChip(_titleCase(ticket.ticketType)),
                    const SizedBox(width: 6),
                    if (paid)
                      const ClientStatusChip('Paid', color: AppTheme.success)
                    else
                      ClientStatusChip(
                        _titleCase(ticket.paymentStatus ?? 'pending'),
                        color: clientStatusColor(
                          ticket.paymentStatus ?? 'pending',
                        ),
                      ),
                    const Spacer(),
                    Text(
                      clientDate(ticket.purchaseDate, fallback: ''),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
                if ((ticket.barcode ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Ticket ID ${ticket.barcode}',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppTheme.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _titleCase(String value) {
  if (value.isEmpty) return value;
  return value[0].toUpperCase() + value.substring(1);
}
