class ClientEventModel {
  final int id;
  final String? customId;
  final String name;
  final String? category;
  final String? eventType;
  final String? eventDate;
  final String? eventTime;
  final String? address;
  final String? state;
  final double price;
  final String status;
  final String? imagePath;
  final String? absoluteImageUrl;
  final int? ticketCount;
  final int? totalTickets;
  final int? maxCapacity;
  final int salesCount;
  final int attendeeCount;
  final String? tag;
  final String? createdAt;
  final double regularPrice;
  final double vipPrice;
  final double premiumPrice;
  final String? ticketTypeMode;

  const ClientEventModel({
    required this.id,
    this.customId,
    required this.name,
    this.category,
    this.eventType,
    this.eventDate,
    this.eventTime,
    this.address,
    this.state,
    this.price = 0,
    this.status = 'draft',
    this.imagePath,
    this.absoluteImageUrl,
    this.ticketCount,
    this.totalTickets,
    this.maxCapacity,
    this.salesCount = 0,
    this.attendeeCount = 0,
    this.tag,
    this.createdAt,
    this.regularPrice = 0,
    this.vipPrice = 0,
    this.premiumPrice = 0,
    this.ticketTypeMode,
  });

  bool get isLive => status.toLowerCase() == 'published';
  bool get isFree => price <= 0;

  int? get capacity => maxCapacity ?? totalTickets;

  factory ClientEventModel.fromJson(
    Map<String, dynamic> json, {
    String? baseOrigin,
  }) {
    double toDouble(dynamic value) {
      if (value == null) return 0;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString()) ?? 0;
    }

    int? toInt(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toInt();
      return int.tryParse(value.toString());
    }

    var imagePath = json['image_path']?.toString();
    var absoluteImage = json['absolute_image_url']?.toString();
    if (imagePath != null &&
        imagePath.isNotEmpty &&
        !imagePath.startsWith('http') &&
        baseOrigin != null &&
        baseOrigin.isNotEmpty) {
      absoluteImage =
          '$baseOrigin/${imagePath.replaceFirst(RegExp(r'^/'), '')}';
    }

    return ClientEventModel(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      customId: json['custom_id']?.toString(),
      name: (json['event_name'] ?? 'Event').toString(),
      category: json['category']?.toString(),
      eventType: json['event_type']?.toString(),
      eventDate: json['event_date']?.toString(),
      eventTime: json['event_time']?.toString(),
      address: json['address']?.toString(),
      state: json['state']?.toString(),
      price: toDouble(json['price']),
      status: (json['status'] ?? 'draft').toString(),
      imagePath: imagePath,
      absoluteImageUrl: absoluteImage,
      ticketCount: toInt(json['ticket_count']),
      totalTickets: toInt(json['total_tickets']),
      maxCapacity: toInt(json['max_capacity']),
      salesCount: toInt(json['sales_count']) ?? 0,
      attendeeCount: toInt(json['attendee_count']) ?? 0,
      tag: json['tag']?.toString(),
      createdAt: json['created_at']?.toString(),
      // The API merges the event metadata into each row, so the per-tier
      // prices the web Events table prints are available here too.
      regularPrice: toDouble(json['regular_price']),
      vipPrice: toDouble(json['vip_price']),
      premiumPrice: toDouble(json['premium_price']),
      ticketTypeMode: json['ticket_type_mode']?.toString(),
    );
  }
}
