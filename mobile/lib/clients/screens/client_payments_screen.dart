import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../models/client_payment_model.dart';
import '../providers/client_auth_provider.dart';
import '../providers/client_data_provider.dart';
import '../widgets/client_detail_sheets.dart';
import '../widgets/client_ui.dart';

class ClientPaymentsScreen extends StatefulWidget {
  const ClientPaymentsScreen({super.key});

  @override
  State<ClientPaymentsScreen> createState() => _ClientPaymentsScreenState();
}

class _ClientPaymentsScreenState extends State<ClientPaymentsScreen> {
  String _filter = 'All';

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<ClientAuthProvider>();
    final data = context.watch<ClientDataProvider>();
    final clientId = auth.client?.profileId;
    final all = data.payments;
    final visible = all.where((payment) {
      if (_filter == 'All') return true;
      return payment.status.toLowerCase() == _filter.toLowerCase();
    }).toList();

    final paid = all.where((p) => p.isPaid);
    final revenue = paid.fold<double>(0, (sum, p) => sum + p.amount);
    final pending = all
        .where((p) => p.status.toLowerCase() == 'pending')
        .fold<double>(0, (sum, p) => sum + p.amount);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Payments'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (clientId != null) await data.refresh(clientId);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.brandRed,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Total revenue',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    clientMoney(revenue),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _heroMetric('${paid.length}', 'Successful'),
                      const SizedBox(width: 22),
                      _heroMetric(
                        clientMoney(pending),
                        'Pending',
                        valueSize: 13,
                      ),
                      const SizedBox(width: 22),
                      _heroMetric('${all.length}', 'Records'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['All', 'Paid', 'Pending', 'Failed']
                    .map(
                      (filter) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(
                            filter,
                            style: TextStyle(
                              color: _filter == filter
                                  ? Colors.white
                                  : AppTheme.textMain,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          selected: _filter == filter,
                          selectedColor: AppTheme.primary,
                          checkmarkColor: Colors.white,
                          onSelected: (_) => setState(() => _filter = filter),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 14),
            if (data.isLoading && all.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (visible.isEmpty)
              const ClientEmptyState(
                icon: Icons.payments_outlined,
                title: 'No payments here',
                message:
                    'Successful, pending and failed transactions show up here.',
              )
            else
              ...visible.map((payment) => _paymentCard(payment)),
            const SizedBox(height: 8),
            const Text(
              'Revenue reflects successful ticket payments on your events. '
              'Payouts settle through your connected Paystack account.',
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.textMuted,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroMetric(String value, String label, {double valueSize = 15}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontSize: valueSize,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 10.5),
        ),
      ],
    );
  }

  Widget _paymentCard(ClientPaymentModel payment) {
    final color = clientStatusColor(payment.status);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => showClientPaymentDetails(context, payment),
      onLongPress: payment.reference.isEmpty
          ? null
          : () async {
              await Clipboard.setData(ClipboardData(text: payment.reference));
              if (!mounted) return;
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text('Reference ${payment.reference} copied'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
            },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEDEFF3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    payment.eventName ?? 'Event payment',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                ClientStatusChip(_titleCase(payment.status), color: color),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        payment.buyerName ?? 'Attendee',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${payment.formattedDate ?? clientDate(payment.createdAt)}'
                        ' · ${payment.ticketCount} ticket${payment.ticketCount == 1 ? '' : 's'}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  clientMoney(payment.amount),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: payment.isPaid ? AppTheme.textMain : color,
                  ),
                ),
              ],
            ),
            if (payment.reference.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Ref ${payment.reference}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppTheme.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _titleCase(String value) {
  if (value.isEmpty) return value;
  return value[0].toUpperCase() + value.substring(1);
}
