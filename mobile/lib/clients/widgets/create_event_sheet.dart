import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/event_utils.dart';
import '../services/client_api_service.dart';

/// Opens the create-event sheet. Returns true when an event was created.
Future<bool> showCreateEventSheet(BuildContext context) async {
  final created = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppTheme.bgPage,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const CreateEventSheet(),
  );
  return created == true;
}

/// Field-for-field port of the website's "Create Event" modal
/// (`client/js/create-event.js`): banner, event name, category, description,
/// full venue address, date/time, state(s), contacts, ticket pricing,
/// visibility and the auto-generated tag/share link.
class CreateEventSheet extends StatefulWidget {
  const CreateEventSheet({super.key});

  @override
  State<CreateEventSheet> createState() => _CreateEventSheetState();
}

class _CreateEventSheetState extends State<CreateEventSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _phone2Ctrl = TextEditingController();
  final _regularPriceCtrl = TextEditingController();
  final _vipPriceCtrl = TextEditingController();
  final _premiumPriceCtrl = TextEditingController();
  final _regularQtyCtrl = TextEditingController();
  final _vipQtyCtrl = TextEditingController();
  final _premiumQtyCtrl = TextEditingController();

  Uint8List? _imageBytes;
  String? _imageName;
  String? _category;
  final Set<String> _selectedStates = <String>{};
  DateTime? _date;
  TimeOfDay? _time;
  String _listingType = 'ticketed';
  String _capacityTier = '0-100';

  static const Map<String, int> _listingFees = {
    'ads_only': 500,
    '0-100': 1000,
    '101-250': 1500,
    '251-500': 2000,
    '501-1000': 2500,
    '1001-unlimited': 3000,
  };
  bool _privateEvent = false;
  final Set<String> _tiers = <String>{};
  bool _submitting = false;
  String? _error;

  // Same vocabularies the website form offers. Loaded from the API so the two
  // portals never drift; the bundled EventUtils copies are the offline fallback.
  List<String> _categories = List<String>.of(EventUtils.eventCategories);
  List<String> _states = List<String>.of(EventUtils.nigeriaStates);

  static final _nameRule = RegExp(
    r"^[A-Za-zÀ-ÖØ-öø-ÿ][A-Za-zÀ-ÖØ-öø-ÿ'. -]*$",
  );
  static final _phoneRule = RegExp(r'^\+?[0-9][0-9\s\-]{6,17}$');

  @override
  void initState() {
    super.initState();
    _loadFormOptions();
  }

  Future<void> _loadFormOptions() async {
    final options = await ClientApiService.fetchEventFormOptions();
    if (!mounted || options == null) return;
    setState(() {
      if (options.categories.isNotEmpty) {
        _categories = List<String>.of(options.categories);
      }
      if (options.states.isNotEmpty) {
        _states = List<String>.of(options.states);
      }
    });
  }

  @override
  void dispose() {
    for (final controller in [
      _nameCtrl,
      _descriptionCtrl,
      _addressCtrl,
      _phoneCtrl,
      _phone2Ctrl,
      _regularPriceCtrl,
      _vipPriceCtrl,
      _premiumPriceCtrl,
      _regularQtyCtrl,
      _vipQtyCtrl,
      _premiumQtyCtrl,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Labels the website shows for the categories whose option text is longer
  /// than the stored value (the API value is what the server expects).
  static const _categoryLabels = {
    'Entertainment': 'Entertainment (Music, Film, Comedy, etc)',
    'Sport & Fitness': 'Sports & Fitness',
    'Personal': 'Personal (Wedding, Anniversary, etc.)',
  };

  String _categoryLabel(String value) => _categoryLabels[value] ?? value;

  Future<void> _pickImage() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _imageName = picked.name.isEmpty ? 'event.jpg' : picked.name;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not open your photo library.');
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Select event date',
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 18, minute: 0),
      helpText: 'Select start time',
    );
    if (picked != null && mounted) setState(() => _time = picked);
  }

  Future<void> _pickStates() async {
    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) {
        final working = <String>{..._selectedStates};
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text(
              'Select State(s)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 340,
              child: ListView.builder(
                itemCount: _states.length,
                itemBuilder: (context, index) {
                  final state = _states[index];
                  final checked = working.contains(state);
                  return CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(state, style: const TextStyle(fontSize: 13.5)),
                    value: checked,
                    onChanged: (value) => setDialogState(() {
                      if (value == true) {
                        working.add(state);
                      } else {
                        working.remove(state);
                      }
                    }),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, working),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.brandRed,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Done'),
              ),
            ],
          ),
        );
      },
    );
    if (selected == null || !mounted) return;
    setState(() {
      _selectedStates
        ..clear()
        ..addAll(selected);
    });
  }

  String _tierLabel(String tier) => tier.toLowerCase() == 'vip'
      ? 'VIP'
      : '${tier[0].toUpperCase()}${tier.substring(1)}';

  double _tierPrice(String tier) {
    final raw = switch (tier) {
      'vip' => _vipPriceCtrl.text,
      'premium' => _premiumPriceCtrl.text,
      _ => _regularPriceCtrl.text,
    };
    return double.tryParse(raw.trim()) ?? 0;
  }

  TextEditingController _priceCtrl(String tier) => switch (tier) {
    'vip' => _vipPriceCtrl,
    'premium' => _premiumPriceCtrl,
    _ => _regularPriceCtrl,
  };

  TextEditingController _qtyCtrl(String tier) => switch (tier) {
    'vip' => _vipQtyCtrl,
    'premium' => _premiumQtyCtrl,
    _ => _regularQtyCtrl,
  };

  /// Web parity: lowercase, strip everything but letters/digits/spaces/dashes,
  /// spaces become single hyphens.
  String get _eventTag {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return '';
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-');
  }

  String get _shareLink {
    final tag = _eventTag;
    if (tag.isEmpty) return '';
    return '${ApiClient().baseOrigin ?? ''}/e/$tag';
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_imageBytes == null) {
      setState(() => _error = 'Add a banner image — required for every event.');
      return;
    }
    if (_date == null || _time == null) {
      setState(() => _error = 'Choose the event date and start time.');
      return;
    }
    if (_category == null) {
      setState(() => _error = 'Choose a category.');
      return;
    }
    if (_selectedStates.isEmpty) {
      setState(() => _error = 'Select at least one state.');
      return;
    }
    if (!_formKey.currentState!.validate()) {
      setState(() => _error = 'Please fix the highlighted fields.');
      return;
    }
    final when = DateTime(
      _date!.year,
      _date!.month,
      _date!.day,
      _time!.hour,
      _time!.minute,
    );
    if (!when.isAfter(DateTime.now())) {
      setState(() => _error = 'Event date and time must be in the future.');
      return;
    }
    if (_listingType == 'ticketed') {
      if (!_listingFees.containsKey(_capacityTier)) {
        setState(() => _error = 'Choose an event capacity bracket.');
        return;
      }
      if (_tiers.isEmpty) {
        setState(() => _error = 'Choose at least one ticket category.');
        return;
      }
      if (_tiers.any((tier) => _tierPrice(tier) <= 0)) {
        setState(() => _error = 'Enter a price above zero for each ticket type.');
        return;
      }

      var totalQuantity = 0;
      for (final tier in _tiers) {
        final quantity = int.tryParse(_qtyCtrl(tier).text.trim());
        if (quantity == null || quantity <= 0) {
          setState(() => _error =
              'Enter a quantity above zero for every selected ticket type.');
          return;
        }
        totalQuantity += quantity;
      }

      final capacityLimit = switch (_capacityTier) {
        '0-100' => 100,
        '101-250' => 250,
        '251-500' => 500,
        '501-1000' => 1000,
        _ => null,
      };
      final capacityMinimum = switch (_capacityTier) {
        '101-250' => 101,
        '251-500' => 251,
        '501-1000' => 501,
        '1001-unlimited' => 1001,
        _ => 1,
      };

      if (totalQuantity < capacityMinimum ||
          (capacityLimit != null && totalQuantity > capacityLimit)) {
        setState(() => _error =
            'Combined ticket quantities must fit the selected $_capacityTier capacity bracket.');
        return;
      }
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final dateText = DateFormat('yyyy-MM-dd').format(when);
      // The website's time picker submits "hh:mm AM/PM"; keep the exact same
      // format so events read the same on both portals.
      final timeText = DateFormat('hh:mm a').format(when);
      final tierList = _tiers.toList();
      final states = _selectedStates.join(',');
      final address = _addressCtrl.text.trim();
      final basePrice = _listingType == 'ads_only'
          ? 0.0
          : tierList.map(_tierPrice).reduce((a, b) => a < b ? a : b);

      final form = FormData();
      void field(String key, String value) =>
          form.fields.add(MapEntry(key, value));

      field('event_name', _nameCtrl.text.trim());
      field('event_type', _category!);
      field('description', _descriptionCtrl.text.trim());
      field('event_date', dateText);
      field('event_time', timeText);
      field('phone_contact_1', _phoneCtrl.text.trim());
      if (_phone2Ctrl.text.trim().isNotEmpty) {
        field('phone_contact_2', _phone2Ctrl.text.trim());
      }
      field('state', states);
      field('address', address);
      field('event_visibility', _privateEvent ? 'private' : 'public');
      field('status', 'draft');
      field(
        'locations_json',
        jsonEncode([
          for (final state in _selectedStates) {'state': state, 'address': address},
        ]),
      );
      field('listing_type', _listingType);
      field('price', basePrice.toStringAsFixed(2));
      if (_listingType == 'ticketed') {
        field('capacity_tier', _capacityTier);
        field('ticket_type', tierList.join(','));
        for (final tier in tierList) {
          field('ticket_type_mode[]', tier);
          field('${tier}_price', _tierPrice(tier).toStringAsFixed(2));
          field('${tier}_quantity', _qtyCtrl(tier).text.trim());
        }
      }
      form.files.add(
        MapEntry(
          'event_image',
          MultipartFile.fromBytes(
            _imageBytes!,
            filename: _imageName ?? 'event.jpg',
          ),
        ),
      );

      final eventId = await ClientApiService.createEvent(form);
      if (!mounted) return;
      _lastCreatedEventId = eventId > 0 ? eventId : null;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'EVENTOUT',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                          color: AppTheme.brandRed,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Create Event',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                children: [
                  _bannerPicker(),
                  const SizedBox(height: 18),
                  _label('Event name *'),
                  TextFormField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r"[A-Za-zÀ-ÖØ-öø-ÿ'. -]"),
                      ),
                    ],
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Enter event name',
                    ),
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.isEmpty) return 'Event name is required';
                      if (!_nameRule.hasMatch(text)) {
                        return 'Letters only (no digits or symbols)';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  _label('Category *'),
                  DropdownButtonFormField<String>(
                    initialValue: _category,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      hintText: 'Select Category',
                    ),
                    items: _categories
                        .map(
                          (category) => DropdownMenuItem(
                            value: category,
                            child: Text(
                              _categoryLabel(category),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _category = value),
                    validator: (value) =>
                        value == null ? 'Choose a category' : null,
                  ),
                  const SizedBox(height: 16),
                  _label('Description *'),
                  TextFormField(
                    controller: _descriptionCtrl,
                    maxLines: 4,
                    maxLength: 600,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      alignLabelWithHint: true,
                      hintText: 'Describe what attendees can expect...',
                    ),
                    validator: (value) => (value?.trim().isEmpty ?? true)
                        ? 'Description is required'
                        : null,
                  ),
                  _label('Full venue address *'),
                  TextFormField(
                    controller: _addressCtrl,
                    maxLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      alignLabelWithHint: true,
                      hintText: 'Street address, landmarks...',
                    ),
                    validator: (value) => (value?.trim().isEmpty ?? true)
                        ? 'Address is required'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label('Date *'),
                            _pickerTile(
                              value: _date == null
                                  ? 'Select date...'
                                  : DateFormat('MMM d, yyyy').format(_date!),
                              icon: Icons.calendar_today_outlined,
                              onTap: _pickDate,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label('Time *'),
                            _pickerTile(
                              value: _time == null
                                  ? 'Select time...'
                                  : _time!.format(context),
                              icon: Icons.schedule,
                              onTap: _pickTime,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _label('State(s) *'),
                  _pickerTile(
                    value: _selectedStates.isEmpty
                        ? 'Select State(s)'
                        : _selectedStates.join(', '),
                    icon: Icons.map_outlined,
                    onTap: _pickStates,
                  ),
                  const SizedBox(height: 16),
                  _label('Primary contact *'),
                  TextFormField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s-]')),
                    ],
                    decoration: const InputDecoration(hintText: '+234...'),
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.isEmpty) return 'Primary contact is required';
                      if (!_phoneRule.hasMatch(text)) {
                        return 'Enter a valid phone number';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  _label('Secondary contact'),
                  TextFormField(
                    controller: _phone2Ctrl,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s-]')),
                    ],
                    decoration: const InputDecoration(
                      hintText: '+234... (optional)',
                    ),
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.isEmpty) return null;
                      return _phoneRule.hasMatch(text)
                          ? null
                          : 'Enter a valid phone number';
                    },
                  ),
                  const SizedBox(height: 18),
                  _label('Listing option *'),
                  DropdownButtonFormField<String>(
                    initialValue: _listingType,
                    isExpanded: true,
                    decoration: const InputDecoration(),
                    items: const [
                      DropdownMenuItem(
                        value: 'ads_only',
                        child: Text('Ads Only - NGN 500'),
                      ),
                      DropdownMenuItem(
                        value: 'ticketed',
                        child: Text('Ads with Events & Ticketing'),
                      ),
                    ],
                    onChanged: (value) => setState(() {
                      _listingType = value ?? 'ticketed';
                      if (_listingType == 'ads_only') _tiers.clear();
                    }),
                  ),
                  const SizedBox(height: 8),
                  if (_listingType == 'ads_only') ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Ads Only listing fee: NGN 500. This option does not include ticket sales, attendee checkout or ticket issuance.',
                        style: TextStyle(fontSize: 12, height: 1.4),
                      ),
                    ),
                  ] else ...[
                    _label('Event capacity bracket *'),
                    DropdownButtonFormField<String>(
                      initialValue: _capacityTier,
                      isExpanded: true,
                      decoration: const InputDecoration(),
                      items: const [
                        DropdownMenuItem(value: '0-100', child: Text('0-100 attendees - NGN 1,000')),
                        DropdownMenuItem(value: '101-250', child: Text('101-250 attendees - NGN 1,500')),
                        DropdownMenuItem(value: '251-500', child: Text('251-500 attendees - NGN 2,000')),
                        DropdownMenuItem(value: '501-1000', child: Text('501-1,000 attendees - NGN 2,500')),
                        DropdownMenuItem(value: '1001-unlimited', child: Text('1,001+ attendees - NGN 3,000')),
                      ],
                      onChanged: (value) =>
                          setState(() => _capacityTier = value ?? '0-100'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Listing fee: NGN ${_listingFees[_capacityTier] ?? 1000}. Combined ticket quantities must fit this bracket.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _label('Select ticket categories *'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (final tier in ['regular', 'vip', 'premium'])
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                right: tier == 'premium' ? 0 : 8,
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => setState(() {
                                  if (!_tiers.remove(tier)) _tiers.add(tier);
                                }),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: _tiers.contains(tier)
                                        ? AppTheme.brandRed.withValues(alpha: 0.06)
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _tiers.contains(tier)
                                          ? AppTheme.brandRed
                                          : const Color(0xFFE2E8F0),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(
                                        _tiers.contains(tier)
                                            ? Icons.check_box_outlined
                                            : Icons.check_box_outline_blank,
                                        size: 18,
                                        color: _tiers.contains(tier)
                                            ? AppTheme.brandRed
                                            : AppTheme.textMuted,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _tierLabel(tier),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    for (final tier in ['regular', 'vip', 'premium'])
                      if (_tiers.contains(tier)) ...[
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextFormField(
                                controller: _priceCtrl(tier),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(
                                  labelText: '${_tierLabel(tier)} price (NGN)',
                                  hintText: 'e.g. 5000',
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: _qtyCtrl(tier),
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Quantity *',
                                  hintText: 'Required',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                  ],
                  const SizedBox(height: 4),
                  _label('Visibility'),
                  DropdownButtonFormField<bool>(
                    initialValue: _privateEvent,
                    isExpanded: true,
                    decoration: const InputDecoration(),
                    items: const [
                      DropdownMenuItem(
                        value: false,
                        child: Text('🌐 Public'),
                      ),
                      DropdownMenuItem(
                        value: true,
                        child: Text('🔒 Private'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _privateEvent = value ?? false),
                  ),
                  if (_privateEvent) ...[
                    const SizedBox(height: 6),
                    const Text(
                      'Private events are saved as drafts too. Complete the listing payment, then publish to activate the private share link.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textMuted,
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.2),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.link,
                              size: 16,
                              color: AppTheme.brandRed,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'AUTO-GENERATED LINKS',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                                color: AppTheme.brandRed,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _label('Event tag'),
                        _readOnlyField(
                          _eventTag.isEmpty
                              ? 'Enter event name first...'
                              : _eventTag,
                        ),
                        const SizedBox(height: 12),
                        _label('Shareable link'),
                        _readOnlyField(
                          _shareLink.isEmpty
                              ? 'Enter event name first...'
                              : _shareLink,
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.error,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: _submitting ? null : _submit,
                          child: _submitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Create Event'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _submitting
                              ? null
                              : () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: AppTheme.textMuted,
      ),
    ),
  );

  Widget _readOnlyField(String value) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFEDEFF3)),
    ),
    child: Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: AppTheme.brandRed,
      ),
    ),
  );

  Widget _bannerPicker() {
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        height: 168,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: _imageBytes == null
            ? const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 34,
                    color: AppTheme.primary,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Upload Banner *',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'JPG, PNG or WebP up to 10 MB',
                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  ),
                ],
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(_imageBytes!, fit: BoxFit.cover),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Change',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _pickerTile({
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppTheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The id of the most recently created event, so the caller can open its
/// preview (Make payment / Publish event) right after the sheet closes.
int? _lastCreatedEventId;

int? takeLastCreatedEventId() {
  final id = _lastCreatedEventId;
  _lastCreatedEventId = null;
  return id;
}
