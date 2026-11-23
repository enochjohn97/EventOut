import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../models/client_event_model.dart';
import '../providers/client_auth_provider.dart';
import '../providers/client_data_provider.dart';
import '../widgets/client_detail_sheets.dart';
import '../widgets/client_ui.dart';

class ClientEventsScreen extends StatefulWidget {
  final Future<void> Function() onCreateEvent;

  const ClientEventsScreen({super.key, required this.onCreateEvent});

  @override
  State<ClientEventsScreen> createState() => _ClientEventsScreenState();
}

class _ClientEventsScreenState extends State<ClientEventsScreen> {
  final _searchCtrl = TextEditingController();
  final _scroll = ScrollController();
  String _filter = 'All';
  String _query = '';
  bool _searchCollapsed = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  /// Collapses the search field into the app bar while the organizer scrolls,
  /// then restores it as soon as they return to the top of the list.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final collapsed = _scroll.offset > 24;
    if (collapsed == _searchCollapsed) return;
    setState(() => _searchCollapsed = collapsed);
  }

  void _revealSearch() {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
    setState(() => _searchCollapsed = false);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<ClientEventModel> _visible(List<ClientEventModel> all) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return all.where((event) {
      if (_query.trim().isNotEmpty) {
        final haystack =
            '${event.name} ${event.state ?? ''} '
                    '${event.category ?? ''}'
                .toLowerCase();
        if (!haystack.contains(_query.trim().toLowerCase())) return false;
      }
      final raw = event.eventDate;
      final parsed = raw == null
          ? null
          : DateTime.tryParse(raw.trim().split(' ').first);
      final passed =
          parsed != null &&
          DateTime(parsed.year, parsed.month, parsed.day).isBefore(today);
      switch (_filter) {
        case 'Live':
          return event.isLive;
        case 'Drafts':
          return event.status.toLowerCase() == 'draft';
        case 'Upcoming':
          return !passed;
        case 'Passed':
          return passed;
        default:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<ClientAuthProvider>();
    final data = context.watch<ClientDataProvider>();
    final clientId = auth.client?.profileId;
    final events = _visible(data.events);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Events'),
        actions: [
          if (_searchCollapsed)
            IconButton(
              tooltip: 'Search events',
              onPressed: _revealSearch,
              icon: const Icon(Icons.search),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'client-create-event',
        onPressed: () => widget.onCreateEvent(),
        backgroundColor: AppTheme.brandRed,
        foregroundColor: Colors.white,
        tooltip: 'Create event',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          if (!_searchCollapsed)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (value) => setState(() => _query = value),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search your events',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear',
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.close),
                        ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['All', 'Live', 'Drafts', 'Upcoming', 'Passed']
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
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                if (clientId != null) await data.refresh(clientId);
              },
              child: ListView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                children: [
                  if (data.isLoading && data.events.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 60),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (events.isEmpty)
                    ClientEmptyState(
                      icon: Icons.event_outlined,
                      title: _query.isEmpty && _filter == 'All'
                          ? 'No events yet'
                          : 'No matching events',
                      message: _query.isEmpty && _filter == 'All'
                          ? 'Create an event ad to reach attendees on the app and website.'
                          : 'Try a different search or filter.',
                      action: ElevatedButton.icon(
                        onPressed: widget.onCreateEvent,
                        icon: const Icon(Icons.add),
                        label: const Text('Create event'),
                      ),
                    )
                  else ...[
                    Text(
                      '${events.length} event${events.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...events.map((event) => _eventCard(event)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _eventCard(ClientEventModel event) {
    final image =
        event.absoluteImageUrl ??
        (event.imagePath != null
            ? ApiClient().absoluteUrl(event.imagePath)
            : null);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFEDEFF3)),
        ),
        child: InkWell(
          onTap: () => showClientEventDetails(
            context,
            event,
            onChanged: () async {
              final id = context.read<ClientAuthProvider>().client?.profileId;
              if (id != null) {
                await context.read<ClientDataProvider>().refresh(id);
              }
            },
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 130,
                width: double.infinity,
                child: image != null && image.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: image,
                        httpHeaders: ApiClient().imageHeadersFor(image),
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => _imageFallback(),
                      )
                    : _imageFallback(),
              ),
              Padding(
                padding: const EdgeInsets.all(13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            event.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              height: 1.25,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ClientStatusChip(
                          _titleCase(event.status),
                          color: clientStatusColor(event.status),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.place_outlined,
                          size: 13,
                          color: AppTheme.textMuted,
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            event.address ?? event.state ?? 'Venue TBC',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 14,
                      runSpacing: 6,
                      children: [
                        _metric(
                          Icons.calendar_today_outlined,
                          clientDate(event.eventDate),
                        ),
                        _metric(
                          Icons.confirmation_number_outlined,
                          '${event.salesCount} sold',
                        ),
                        _metric(
                          Icons.inventory_2_outlined,
                          event.capacity == null
                              ? 'Unlimited'
                              : '${event.capacity} capacity',
                        ),
                        _metric(Icons.sell_outlined, clientEventPrice(event)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metric(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppTheme.primary),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AppTheme.textMain,
          ),
        ),
      ],
    );
  }

  Widget _imageFallback() => Container(
    color: AppTheme.primary.withValues(alpha: 0.08),
    child: const Center(
      child: Icon(Icons.event, color: AppTheme.primary, size: 32),
    ),
  );
}

String _titleCase(String value) {
  if (value.isEmpty) return value;
  return value[0].toUpperCase() + value.substring(1);
}
