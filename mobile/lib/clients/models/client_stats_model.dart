class ClientStatsModel {
  final double totalRevenue;
  final int totalTickets;
  final int totalEvents;
  final int upcomingEvents;
  final int totalUsers;
  final int totalMedia;

  const ClientStatsModel({
    this.totalRevenue = 0,
    this.totalTickets = 0,
    this.totalEvents = 0,
    this.upcomingEvents = 0,
    this.totalUsers = 0,
    this.totalMedia = 0,
  });

  factory ClientStatsModel.fromJson(Map<String, dynamic> json) {
    double toDouble(dynamic value) {
      if (value == null) return 0;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString()) ?? 0;
    }

    int toInt(dynamic value) {
      if (value == null) return 0;
      if (value is num) return value.toInt();
      return int.tryParse(value.toString()) ?? 0;
    }

    return ClientStatsModel(
      totalRevenue: toDouble(json['total_revenue']),
      totalTickets: toInt(json['total_tickets']),
      totalEvents: toInt(json['total_events']),
      upcomingEvents: toInt(json['upcoming_events']),
      totalUsers: toInt(json['total_users']),
      totalMedia: toInt(json['total_media']),
    );
  }

  Map<String, dynamic> toJson() => {
    'total_revenue': totalRevenue,
    'total_tickets': totalTickets,
    'total_events': totalEvents,
    'upcoming_events': upcomingEvents,
    'total_users': totalUsers,
    'total_media': totalMedia,
  };
}
