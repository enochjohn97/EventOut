import 'package:flutter/foundation.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/secure_storage.dart';
import '../../core/utils/load_timings.dart';
import '../models/ticket_model.dart';
import '../services/user_ticket_service.dart';

class TicketsProvider extends ChangeNotifier {
  List<TicketModel> tickets = [];
  bool isLoading = false;
  String? error;

  Future<void> load() async {
    final timer = LoadTimings.start();
    isLoading = true;
    error = null;
    notifyListeners();
    // Paint the secure-store mirror first so the list renders in well under a
    // second; the network refresh replaces it as soon as it lands.
    if (tickets.isEmpty) {
      try {
        final cached = await SecureStorage.getPrivateList('tickets');
        if (cached != null && cached.isNotEmpty && tickets.isEmpty) {
          tickets = cached
              .map(
                (ticket) => TicketModel.fromJson(
                  ticket,
                  baseOrigin: ApiClient().baseOrigin,
                ),
              )
              .toList();
          notifyListeners();
        }
      } catch (_) {
        // A broken cache never blocks the live fetch.
      }
    }
    try {
      tickets = await UserTicketService.getTickets();
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      LoadTimings.stop('tickets_load', timer);
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> resendEmail(TicketModel ticket) async {
    await UserTicketService.sendTicketEmail(
      reference: ticket.reference,
      barcode: ticket.barcode,
      ticketId: ticket.id,
    );
  }
}
