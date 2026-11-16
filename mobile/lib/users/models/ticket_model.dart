class TicketModel {
  final int id;
  final String? customId;
  final String barcode;
  final String ticketType;
  final String status;
  final bool used;
  final String? purchaseDate;
  final int eventId;
  final String? eventCustomId;
  final String eventName;
  final String? eventDate;
  final String? eventTime;
  final String? address;
  final String? location;
  final String? eventImage;
  final String? absoluteEventImage;
  final String? qrCodePath;
  final String? absoluteQrUrl;
  final double amount;
  final String? reference;
  final String? paymentStatus;
  final String? organizerName;

  const TicketModel({
    required this.id,
    this.customId,
    required this.barcode,
    this.ticketType = 'regular',
    this.status = 'valid',
    this.used = false,
    this.purchaseDate,
    required this.eventId,
    this.eventCustomId,
    required this.eventName,
    this.eventDate,
    this.eventTime,
    this.address,
    this.location,
    this.eventImage,
    this.absoluteEventImage,
    this.qrCodePath,
    this.absoluteQrUrl,
    this.amount = 0,
    this.reference,
    this.paymentStatus,
    this.organizerName,
  });

  /// True when the event this ticket belongs to already took place. Archiving
  /// is date-based on the server (event_date < today), so a passed event is
  /// also an archived one — and its ticket can no longer admit entry.
  bool get isEventPassed {
    final raw = eventDate;
    if (raw == null || raw.trim().isEmpty) return false;
    final day = raw.trim().split(RegExp(r'[ T]')).first;
    final parsed = DateTime.tryParse(day);
    if (parsed == null) return false;
    final now = DateTime.now();
    return DateTime(parsed.year, parsed.month, parsed.day)
        .isBefore(DateTime(now.year, now.month, now.day));
  }

  /// Status the app shows: a passed/archived event makes its ticket invalid
  /// even while the ticket row itself is still marked valid.
  String get effectiveStatus => isEventPassed ? 'invalid' : status;

  factory TicketModel.fromJson(Map<String, dynamic> json, {String? baseOrigin}) {
    double toDouble(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0;
    }

    String? eventImage = json['event_image']?.toString();
    String? absEventImage = json['absolute_event_image']?.toString();
    // Re-resolve against the CURRENT API origin (local ↔ live switching) so a
    // cached ticket never keeps pointing at the previous origin's image.
    if (eventImage != null &&
        eventImage.isNotEmpty &&
        !eventImage.startsWith('http') &&
        baseOrigin != null &&
        baseOrigin.isNotEmpty) {
      absEventImage = '$baseOrigin/${eventImage.replaceFirst(RegExp(r'^/'), '')}';
    }

    String? qrPath = json['qr_code_path']?.toString();
    String? absQr = json['absolute_qr_url']?.toString();
    if (qrPath != null &&
        qrPath.isNotEmpty &&
        !qrPath.startsWith('http') &&
        baseOrigin != null &&
        baseOrigin.isNotEmpty) {
      absQr = '$baseOrigin/${qrPath.replaceFirst(RegExp(r'^/'), '')}';
    }

    return TicketModel(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      customId: json['custom_id']?.toString(),
      barcode: json['barcode']?.toString() ?? '',
      ticketType: json['ticket_type']?.toString() ?? 'regular',
      status: json['status']?.toString() ?? 'valid',
      used: json['used'] == true || json['used']?.toString() == '1',
      purchaseDate: json['purchase_date']?.toString(),
      eventId: int.tryParse(json['event_id']?.toString() ?? '') ?? 0,
      eventCustomId: json['event_custom_id']?.toString(),
      eventName: json['event_name']?.toString() ?? 'Event',
      eventDate: json['event_date']?.toString(),
      eventTime: json['event_time']?.toString(),
      address: json['address']?.toString(),
      location: json['location']?.toString(),
      eventImage: eventImage,
      absoluteEventImage: absEventImage,
      qrCodePath: qrPath,
      absoluteQrUrl: absQr,
      amount: toDouble(json['amount']),
      reference: json['reference']?.toString(),
      paymentStatus: json['payment_status']?.toString(),
      organizerName: json['organizer_name']?.toString(),
    );
  }
}
