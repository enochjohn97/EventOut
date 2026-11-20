import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand_logo.dart';
import '../models/client_event_model.dart';
import '../models/client_payment_model.dart';
import '../providers/client_auth_provider.dart';
import '../providers/client_data_provider.dart';
import '../widgets/client_ui.dart';

class ClientHomeScreen extends StatelessWidget {
  final ValueChanged<int> onSelectTab;
  final Future<void> Function() onCreateEvent;

  const ClientHomeScreen({
    super.key,
    required this.onSelectTab,
    required this.onCreateEvent,
  });

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<ClientAuthProvider>();
    final data = context.watch<ClientDataProvider>();
    final client = auth.client;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const BrandLogo(
          size: 27,
          markSize: 23,
          animateEveryMinute: true,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: GestureDetector(
              onTap: () => onSelectTab(4),
              child: ClientAvatar(
                imagePath: client?.profilePic,
                initials: client?.initials ?? 'C',
                radius: 17,
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          final id = client?.profileId;
          if (id != null) await data.refresh(id);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          children: [
            _greeting(context, client?.displayName ?? 'Organizer'),
            const SizedBox(height: 16),
            if (!data.hasLoaded && data.isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              if (data.error != null) ...[
                _errorBanner(data.error!),
                const SizedBox(height: 14),
              ],
              _statsGrid(data),
              const SizedBox(height: 18),
              _quickActions(context),
              ClientSectionHeader(
                'Upcoming events',
                actionLabel: 'See all',
                onAction: () => onSelectTab(1),
              ),
              if (data.upcomingEvents.isEmpty)
                ClientEmptyState(
                  icon: Icons.event_outlined,
                  title: 'No upcoming events',
                  message:
                      'Create your first event ad and start selling tickets.',
                  action: ElevatedButton.icon(
                    onPressed: onCreateEvent,
                    icon: const Icon(Icons.add),
                    label: const Text('Create event'),
                  ),
                )
              else
                ...data.upcomingEvents
                    .take(3)
                    .map((event) => _eventTile(context, event)),
              const SizedBox(height: 10),
              ClientSectionHeader(
                'Recent payments',
                actionLabel: 'See all',
                onAction: () => onSelectTab(3),
              ),
              if (data.recentPayments.isEmpty)
                const ClientEmptyState(
                  icon: Icons.payments_outlined,
                  title: 'No payments yet',
                  message:
                      'Ticket payments appear here as soon as attendees check out.',
                )
              else
                ...data.recentPayments.map(
                  (payment) => _paymentTile(context, payment),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _greeting(BuildContext context, String name) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Welcome back',
          style: TextStyle(
            fontSize: 12.5,
            color: AppTheme.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 3),
        const Text(
          'Here is how your events are performing.',
          style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
        ),
      ],
    );
  }

  Widget _statsGrid(ClientDataProvider data) {
    final stats = data.stats;
    final cards = [
      ClientStatCard(
        label: 'Revenue',
        value: clientMoney(stats.totalRevenue),
        icon: Icons.account_balance_wallet_outlined,
        accent: AppTheme.success,
      ),
      ClientStatCard(
        label: 'Tickets sold',
        value: clientNumber(stats.totalTickets),
        icon: Icons.confirmation_number_outlined,
        accent: AppTheme.brandRed,
      ),
      ClientStatCard(
        label: 'Events',
        value: clientNumber(stats.totalEvents),
        icon: Icons.event_outlined,
      ),
      ClientStatCard(
        label: 'Attendees',
        value: clientNumber(stats.totalUsers),
        icon: Icons.groups_outlined,
        accent: const Color(0xFF0F766E),
      ),
    ];
    // A fixed height (instead of an aspect ratio) keeps the icon, value and
    // label from clipping when the cards get narrower on small phones.
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cards.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: 124,
      ),
      itemBuilder: (context, index) => cards[index],
    );
  }

  Widget _quickActions(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: onCreateEvent,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.brandRed,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                children: [
                  Icon(Icons.add_circle_outline, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Create event',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Icon(Icons.arrow_forward, color: Colors.white, size: 16),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: InkWell(
            onTap: () => onSelectTab(2),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFEDEFF3)),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.qr_code_scanner,
                    color: AppTheme.primary,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tickets',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward,
                    color: AppTheme.textMuted,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _eventTile(BuildContext context, ClientEventModel event) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDEFF3)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 62,
              height: 62,
              child: event.absoluteImageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: event.absoluteImageUrl!,
                      httpHeaders: ApiClient().imageHeadersFor(
                        event.absoluteImageUrl!,
                      ),
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => _eventImageFallback(),
                    )
                  : _eventImageFallback(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${clientDate(event.eventDate)}'
                  '${(event.eventTime ?? '').isNotEmpty ? ' · ${event.eventTime}' : ''}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    ClientStatusChip(
                      _titleCase(event.status),
                      color: clientStatusColor(event.status),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${event.salesCount} sold'
                        '${event.capacity != null ? ' / ${event.capacity}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentTile(BuildContext context, ClientPaymentModel payment) {
    final color = clientStatusColor(payment.status);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDEFF3)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.payments_outlined, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  payment.eventName ?? 'Event payment',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${payment.buyerName ?? 'Attendee'} · '
                  '${payment.formattedDate ?? clientDate(payment.createdAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                clientMoney(payment.amount),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 3),
              ClientStatusChip(_titleCase(payment.status), color: color),
            ],
          ),
        ],
      ),
    );
  }

  Widget _eventImageFallback() => Container(
    color: AppTheme.primary.withValues(alpha: 0.08),
    child: const Icon(Icons.event, color: AppTheme.primary, size: 22),
  );

  Widget _errorBanner(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: const TextStyle(
          fontSize: 12,
          color: AppTheme.error,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

String _titleCase(String value) {
  if (value.isEmpty) return value;
  return value[0].toUpperCase() + value.substring(1);
}
