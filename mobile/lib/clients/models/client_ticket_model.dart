/// Server-side ticket totals from `/tickets/get-tickets` — the same numbers
/// the web Tickets page shows. Revenue splits a payment across its tickets, so
/// it must come from the API (summing payment amounts per ticket row would
/// multiply every multi-ticket order).
class ClientTicketStats {
  final int totalTickets;
  final int pendingTickets;
  final int cancelledTickets;
  final double totalRevenue;
  final bool fromServer;

  const ClientTicketStats({
    this.totalTickets = 0,
    this.pendingTickets = 0,
    this.cancelledTickets = 0,
    this.totalRevenue = 0,
    this.fromServer = false,
  });

  factory ClientTicketStats.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic value) {
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    double toDouble(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    return ClientTicketStats(
      totalTickets: toInt(json['total_tickets']),
      pendingTickets: toInt(json['pending_tickets']),
      cancelledTickets: toInt(json['cancelled_tickets']),
      totalRevenue: toDouble(json['total_revenue']),
      fromServer: true,
    );
  }
}

class ClientTicketModel {
  final int? id;
  final String? customId;
  final String? barcode;
  final String ticketType;
  final String status;
  final bool used;
  final String? purchaseDate;
  final String eventName;
  final String? eventImagePath;
  final String? absoluteEventImage;
  final String? buyerName;
  final double amount;
  final String? paymentStatus;
  final String? reference;
  final String? priceDisplay;

  const ClientTicketModel({
    this.id,
    this.customId,
    this.barcode,
    this.ticketType = 'regular',
    this.status = 'valid',
    required this.eventName,
    this.used = false,
    this.purchaseDate,
    this.eventImagePath,
    this.absoluteEventImage,
    this.buyerName,
    this.amount = 0,
    this.paymentStatus,
    this.reference,
    this.priceDisplay,
  });

  factory ClientTicketModel.fromJson(
    Map<String, dynamic> json, {
    String? baseOrigin,
  }) {
    double toDouble(dynamic value) {
      if (value == null) return 0;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString()) ?? 0;
    }

    final imagePath = json['event_image']?.toString();
    String? absolute = json['absolute_event_image']?.toString();
    if (imagePath != null &&
        imagePath.isNotEmpty &&
        !imagePath.startsWith('http') &&
        baseOrigin != null &&
        baseOrigin.isNotEmpty) {
      absolute = '$baseOrigin/${imagePath.replaceFirst(RegExp(r'^/'), '')}';
    }

    return ClientTicketModel(
      id: int.tryParse(json['id']?.toString() ?? ''),
      customId: json['custom_id']?.toString(),
      barcode: json['barcode']?.toString(),
      ticketType: (json['ticket_type'] ?? 'regular').toString(),
      status: (json['status'] ?? 'valid').toString(),
      used: json['used'] == true || json['used']?.toString() == '1',
      purchaseDate: json['purchase_date']?.toString(),
      eventName: (json['event_name'] ?? 'Event').toString(),
      eventImagePath: imagePath,
      absoluteEventImage: absolute,
      buyerName: json['buyer_name']?.toString(),
      amount: toDouble(json['amount']),
      paymentStatus: json['payment_status']?.toString(),
      reference: json['reference']?.toString(),
      priceDisplay: json['price_display']?.toString(),
    );
  }
}
