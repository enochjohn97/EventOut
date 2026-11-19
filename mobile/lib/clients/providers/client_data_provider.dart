import 'package:flutter/foundation.dart';

import '../models/client_event_model.dart';
import '../models/client_payment_model.dart';
import '../models/client_stats_model.dart';
import '../models/client_ticket_model.dart';
import '../services/client_api_service.dart';

/// Single source of truth for the organizer dashboard data.
///
/// All four lists are fetched in parallel and kept in memory, so switching
/// bottom-navigation tabs never re-hits the network and the screens stay
/// perfectly in sync with the web portal after a pull-to-refresh.
class ClientDataProvider extends ChangeNotifier {
  ClientStatsModel stats = const ClientStatsModel();
  ClientTicketStats ticketStats = const ClientTicketStats();
  List<ClientEventModel> events = const [];
  List<ClientTicketModel> tickets = const [];
  List<ClientPaymentModel> payments = const [];

  bool isLoading = false;
  bool hasLoaded = false;
  String? error;

  int? _clientId;
  int _requestId = 0;

  Future<void> load(int clientId, {bool force = false}) async {
    if (isLoading && !force) return;
    if (hasLoaded && _clientId == clientId && !force) return;
    _clientId = clientId;
    final requestId = ++_requestId;
    isLoading = true;
    error = null;
    notifyListeners();

    try {
      // Each endpoint is independent: one failing call (say, payments) must
      // not blank out the events and tickets the organizer can still use.
      final errors = <String>[];
      // A dashboard-stats failure is not surfaced: the same figures are derived
      // from the lists below, so showing "Unauthorized" next to correct numbers
      // only confused organizers.
      final statsErrors = <String>[];
      final results = await Future.wait<Object?>([
        _safe(ClientApiService.fetchStats(), statsErrors),
        _safe(ClientApiService.fetchEvents(clientId: clientId), errors),
        _safe(ClientApiService.fetchTickets(), errors),
        _safe(ClientApiService.fetchPayments(), errors),
      ]);
      if (requestId != _requestId) return;
      final freshStats = results[0] as ClientStatsModel?;
      final freshEvents = results[1] as List<ClientEventModel>?;
      final freshTickets =
          results[2]
              as ({List<ClientTicketModel> tickets, ClientTicketStats stats})?;
      final freshPayments = results[3] as List<ClientPaymentModel>?;
      if (freshEvents != null) events = freshEvents;
      if (freshTickets != null) {
        tickets = freshTickets.tickets;
        ticketStats = freshTickets.stats.fromServer
            ? freshTickets.stats
            : _ticketTotals(freshTickets.tickets);
      }
      if (freshPayments != null) payments = freshPayments;
      // If the dashboard endpoint is unavailable, derive the same figures the
      // web dashboard shows from the records that did load instead of
      // displaying zeros (which looked like lost revenue/tickets).
      stats = freshStats ?? _derivedStats();
      error = errors.isEmpty ? null : errors.first;
      // Only mark as loaded when at least one endpoint answered, so a fully
      // failed first load is retried on the next tab switch.
      hasLoaded = results.any((result) => result != null);
    } catch (e) {
      if (requestId != _requestId) return;
      error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (requestId == _requestId) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<T?> _safe<T>(Future<T> future, List<String> errors) async {
    try {
      return await future;
    } catch (e) {
      errors.add(e.toString().replaceFirst('Exception: ', ''));
      return null;
    }
  }

  Future<void> refresh(int clientId) => load(clientId, force: true);

  ClientTicketStats _ticketTotals(List<ClientTicketModel> list) {
    return ClientTicketStats(
      totalTickets: list.length,
      pendingTickets: list
          .where((t) => t.status.toLowerCase() == 'pending')
          .length,
      cancelledTickets: list
          .where((t) => t.status.toLowerCase() == 'cancelled')
          .length,
      totalRevenue: list
          .where((t) => (t.paymentStatus ?? '').toLowerCase() == 'paid')
          .fold<double>(0, (sum, t) => sum + t.amount),
    );
  }

  /// Mirrors the server's dashboard aggregation using the loaded records.
  ClientStatsModel _derivedStats() {
    final paid = payments.where((p) => p.isPaid);
    return ClientStatsModel(
      totalRevenue: paid.fold<double>(0, (sum, p) => sum + p.amount),
      totalTickets: tickets.length,
      totalEvents: events.length,
      upcomingEvents: events.length,
      totalUsers: payments
          .map((p) => p.buyerName)
          .whereType<String>()
          .where((name) => name.trim().isNotEmpty)
          .toSet()
          .length,
      totalMedia: stats.totalMedia,
    );
  }

  void reset() {
    stats = const ClientStatsModel();
    ticketStats = const ClientTicketStats();
    events = const [];
    tickets = const [];
    payments = const [];
    hasLoaded = false;
    error = null;
    _clientId = null;
    notifyListeners();
  }

  List<ClientEventModel> get upcomingEvents {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final list = events.where((event) {
      final raw = event.eventDate;
      if (raw == null || raw.trim().isEmpty) return false;
      final parsed = DateTime.tryParse(raw.trim().split(' ').first);
      if (parsed == null) return false;
      return !DateTime(parsed.year, parsed.month, parsed.day).isBefore(today);
    }).toList();
    list.sort((a, b) => (a.eventDate ?? '').compareTo(b.eventDate ?? ''));
    return list;
  }

  List<ClientPaymentModel> get recentPayments {
    final list = [...payments];
    list.sort(
      (a, b) => (b.paidAt ?? b.createdAt ?? '').compareTo(
        a.paidAt ?? a.createdAt ?? '',
      ),
    );
    return list.take(5).toList();
  }
}
