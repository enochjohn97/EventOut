import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../models/client_event_model.dart';
import '../models/client_payment_model.dart';
import '../models/client_stats_model.dart';
import '../models/client_ticket_model.dart';
import 'client_session.dart';

/// Option lists rendered by the create-event form. Served by the web API so
/// both portals offer the same categories and states.
class ClientEventFormOptions {
  final List<String> categories;
  final List<String> states;

  const ClientEventFormOptions({
    required this.categories,
    required this.states,
  });
}

/// Data calls for the organizer portal. Every call reuses the same endpoints
/// as the web client dashboard, so the phone and the website stay in sync.
class ClientApiService {
  static final Dio _dio = ApiClient().dio;
  static String? get _origin => ApiClient().baseOrigin;

  static Map<String, dynamic> _toMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } on FormatException {
        // Fall through to a readable error.
      }
    }
    throw const ApiException(
      'EventOut server returned an invalid response. Please try again.',
    );
  }

  static Future<Response<dynamic>> _send(
    Future<Response<dynamic>> Function() request, {
    bool retried = false,
  }) async {
    try {
      return await request();
    } on DioException catch (error) {
      final code = error.response?.statusCode;
      if (!retried && (code == 401 || code == 403)) {
        final refreshed = await ClientSession.refresh();
        if (refreshed) {
          // Exactly one retry: a persistently rejected token must surface as
          // an error (and force a fresh login) instead of looping.
          return _send(request, retried: true);
        }
      }
      throw apiErrorFromDio(error, 'Could not reach EventOut. Try again.');
    }
  }

  static Options _options({bool json = true, bool retry = false}) => Options(
    headers: ClientSession.headers(json: json),
    extra: ClientSession.requestExtra(retry: retry),
  );

  static Future<ClientStatsModel> fetchStats() async {
    final response = await _send(
      () => _dio.get('/stats/get-client-dashboard-stats', options: _options()),
    );
    final data = _toMap(response.data);
    if (data['success'] != true) {
      throw ApiException(
        data['message']?.toString() ?? 'Could not load your dashboard.',
      );
    }
    return ClientStatsModel.fromJson(
      data['stats'] is Map
          ? Map<String, dynamic>.from(data['stats'] as Map)
          : const <String, dynamic>{},
    );
  }

  static Future<List<ClientEventModel>> fetchEvents({
    required int clientId,
    int limit = 100,
  }) async {
    final response = await _send(
      () => _dio.get(
        '/events',
        queryParameters: {'client_id': clientId, 'limit': limit},
        options: _options(),
      ),
    );
    final data = _toMap(response.data);
    if (data['success'] != true) {
      throw ApiException(
        data['message']?.toString() ?? 'Could not load your events.',
      );
    }
    final list = (data['events'] as List? ?? const []);
    return list
        .whereType<Map>()
        .map(
          (row) => ClientEventModel.fromJson(
            Map<String, dynamic>.from(row),
            baseOrigin: _origin,
          ),
        )
        .toList();
  }

  /// Ticket rows plus the server's totals (sold, revenue, pending, cancelled)
  /// so the phone shows exactly what the web Tickets page shows.
  static Future<({List<ClientTicketModel> tickets, ClientTicketStats stats})>
  fetchTickets() async {
    final response = await _send(
      () => _dio.get('/tickets/get-tickets', options: _options()),
    );
    final data = _toMap(response.data);
    if (data['success'] != true) {
      throw ApiException(
        data['message']?.toString() ?? 'Could not load your tickets.',
      );
    }
    final list = (data['tickets'] as List? ?? const []);
    final tickets = list
        .whereType<Map>()
        .map(
          (row) => ClientTicketModel.fromJson(
            Map<String, dynamic>.from(row),
            baseOrigin: _origin,
          ),
        )
        .toList();
    final rawStats = data['stats'];
    final stats = rawStats is Map
        ? ClientTicketStats.fromJson(Map<String, dynamic>.from(rawStats))
        : const ClientTicketStats();
    return (tickets: tickets, stats: stats);
  }

  static Future<List<ClientPaymentModel>> fetchPayments({
    int limit = 50,
  }) async {
    final response = await _send(
      () => _dio.get(
        '/payments/get-payments',
        queryParameters: {'limit': limit, 'sort': 'date_desc'},
        options: _options(),
      ),
    );
    final data = _toMap(response.data);
    if (data['success'] != true) {
      throw ApiException(
        data['message']?.toString() ?? 'Could not load your payments.',
      );
    }
    final list = (data['payments'] as List? ?? const []);
    return list
        .whereType<Map>()
        .map(
          (row) => ClientPaymentModel.fromJson(
            Map<String, dynamic>.from(row),
            baseOrigin: _origin,
          ),
        )
        .toList();
  }

  static ClientEventFormOptions? _formOptions;

  /// Categories and states for the create-event form. Served by the same API
  /// the website form reads (`/events/form-options`), so the phone form always
  /// lists exactly what the web app lists. Returns null when the endpoint is
  /// unavailable so the caller can fall back to its bundled copy.
  static Future<ClientEventFormOptions?> fetchEventFormOptions() async {
    if (_formOptions != null) return _formOptions;
    try {
      final response = await _dio.get(
        '/events/form-options',
        options: _options(),
      );
      final data = _toMap(response.data);
      if (data['success'] != true) return null;
      List<String> read(dynamic raw) => (raw is List ? raw : const [])
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .toList();
      final options = ClientEventFormOptions(
        categories: read(data['categories']),
        states: read(data['states']),
      );
      if (options.categories.isEmpty) return null;
      _formOptions = options;
      return options;
    } catch (_) {
      return null;
    }
  }

  /// Publishes a draft event — the same endpoint the web "Publish Event Now"
  /// button calls.
  static Future<void> publishEvent(int eventId) async {
    await ClientSession.refresh();
    final response = await _send(
      () => _dio.post(
        '/events/publish-event',
        data: {'event_id': eventId},
        options: _options(),
      ),
    );
    final data = _toMap(response.data);
    if (data['success'] != true) {
      throw ApiException(
        data['message']?.toString() ?? 'Could not publish the event.',
      );
    }
  }

  /// Initializes the server-calculated EventOut listing fee through Paystack.
  static Future<Map<String, dynamic>> initializeListingFeePayment(
    int eventId,
  ) async {
    if (eventId <= 0) {
      throw ApiException('Invalid event ID.');
    }

    await ClientSession.refresh();
    final response = await _send(
      () => _dio.post(
        '/payments/initialize-listing-fee.php',
        data: {'event_id': eventId},
        options: _options(),
      ),
    );

    final data = _toMap(response.data);
    if (data['success'] != true) {
      throw ApiException(
        data['message']?.toString() ?? 'Could not initialize listing payment.',
      );
    }

    final authorizationUrl = data['authorization_url']?.toString() ?? '';
    final uri = Uri.tryParse(authorizationUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'checkout.paystack.com') {
      throw ApiException('The payment provider returned an invalid checkout URL.');
    }

    return data;
  }

  /// Publishes a new event/ads campaign using the same create-event API the
  /// web modal posts to (multipart with the banner image).
  static Future<int> createEvent(FormData form) async {
    // A multipart body cannot safely be replayed after a 401, so make sure the
    // session token is fresh BEFORE uploading the banner and the form.
    await ClientSession.refresh();
    final response = await _send(
      () => _dio.post(
        '/events/create-event',
        data: form,
        options: _options(json: false),
      ),
      retried: true,
    );
    final data = _toMap(response.data);
    if (data['success'] != true) {
      throw ApiException(
        data['message']?.toString() ?? 'Could not create the event.',
      );
    }
    final event = data['event'];
    if (event is Map) {
      return int.tryParse(event['id']?.toString() ?? '') ?? 0;
    }
    return int.tryParse(data['event_id']?.toString() ?? '') ?? 0;
  }

  static int? pendingListingFeeEventId;

  /// Reads the latest listing-fee payment status for this client's event.
  static Future<Map<String, dynamic>> getListingFeeStatus(int eventId) async {
    await ClientSession.refresh();
    final response = await _send(
      () => _dio.get(
        '/payments/listing-fee-status',
        queryParameters: {'event_id': eventId},
        options: _options(),
      ),
      retried: true,
    );
    final data = _toMap(response.data);
    if (data['success'] != true) {
      throw ApiException(
        data['message']?.toString() ?? 'Could not check listing-fee payment.',
      );
    }
    return data;
  }

}
