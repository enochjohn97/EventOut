class ClientPaymentModel {
  final int id;
  final String? customId;
  final String reference;
  final double amount;
  final String status;
  final String? paidAt;
  final String? createdAt;
  final String? eventName;
  final String? eventDate;
  final String? eventImagePath;
  final String? absoluteEventImage;
  final String? buyerName;
  final int ticketCount;
  final String? formattedDate;

  const ClientPaymentModel({
    required this.id,
    this.customId,
    this.reference = '',
    this.amount = 0,
    this.status = 'pending',
    this.paidAt,
    this.createdAt,
    this.eventName,
    this.eventDate,
    this.eventImagePath,
    this.absoluteEventImage,
    this.buyerName,
    this.ticketCount = 0,
    this.formattedDate,
  });

  bool get isPaid => status.toLowerCase() == 'paid';

  factory ClientPaymentModel.fromJson(
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

    return ClientPaymentModel(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      customId: json['custom_id']?.toString(),
      reference: (json['reference'] ?? '').toString(),
      amount: toDouble(json['amount']),
      status: (json['status'] ?? 'pending').toString(),
      paidAt: json['paid_at']?.toString(),
      createdAt: json['created_at']?.toString(),
      eventName: json['event_name']?.toString(),
      eventDate: json['event_date']?.toString(),
      eventImagePath: imagePath,
      absoluteEventImage: absolute,
      buyerName: json['buyer_name']?.toString(),
      ticketCount: int.tryParse(json['ticket_count']?.toString() ?? '') ?? 0,
      formattedDate: json['formatted_date']?.toString(),
    );
  }
}
