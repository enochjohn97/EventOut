import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

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
  final Map<String, TextEditingController> _locationAddressCtrls = {};
  final Map<String, DateTime?> _locationDates = {};
  final Map<String, TimeOfDay?> _locationTimes = {};
  bool _customizeDatesPerState = false;
  DateTime? _date;
  TimeOfDay? _time;
  String _listingType = 'ticketed';
  String _capacityTier = '0-100';
  bool _privateEvent = false;
  final Set<String> _tiers = <String>{};
  bool _submitting = false;
  String? _error;

  // Same vocabularies the website form offers. Loaded from the API so the two
  // portals never drift; the bundled EventUtils copies are the offline fallback.
  List<String> _categories = List<String>.of(EventUtils.eventCategories);
  List<String> _states = List<String>.of(EventUtils.nigeriaStates);

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

  static final _nameRule = RegExp(r"^[A-Za-zÀ-ÖØ-öø-ÿ][A-Za-zÀ-ÖØ-öø-ÿ'. -]*$");
  static final _phoneRule = RegExp(r'^\+?[0-9][0-9\s\-]{6,17}$');

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
    for (final controller in _locationAddressCtrls.values) {
      controller.dispose();
    }
    super.dispose();
  }

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


  Future<void> _chooseStates() async {
    final selected = Set<String>.of(_selectedStates);

    final result = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, refreshDialog) {
            return AlertDialog(
              title: const Text('Select event states'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: _states.map((state) {
                    return CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(state),
                      value: selected.contains(state),
                      onChanged: (checked) {
                        refreshDialog(() {
                          if (checked == true) {
                            selected.add(state);
                          } else {
                            selected.remove(state);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(
                    dialogContext,
                    Set<String>.of(selected),
                  ),
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null || !mounted) return;

    setState(() {
      final removed = _selectedStates.difference(result);
      for (final state in removed) {
        _locationAddressCtrls.remove(state)?.dispose();
        _locationDates.remove(state);
        _locationTimes.remove(state);
      }

      _selectedStates
        ..clear()
        ..addAll(result);

      for (final state in _selectedStates) {
        _locationAddressCtrls.putIfAbsent(
          state,
          () => TextEditingController(),
        );
      }

      if (_selectedStates.length < 2) {
        _customizeDatesPerState = false;
      }
    });
  }

  Future<void> _pickLocationDate(String state) async {
    final now = DateTime.now();
    final current = _locationDates[state];
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? _date ?? now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Select date for $state',
    );
    if (picked != null && mounted) {
      setState(() => _locationDates[state] = picked);
    }
  }

  Future<void> _pickLocationTime(String state) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _locationTimes[state] ??
          _time ??
          const TimeOfDay(hour: 18, minute: 0),
      helpText: 'Select start time for $state',
    );
    if (picked != null && mounted) {
      setState(() => _locationTimes[state] = picked);
    }
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

  int _tierQuantity(String tier) {
    final raw = switch (tier) {
      'vip' => _vipQtyCtrl.text,
      'premium' => _premiumQtyCtrl.text,
      _ => _regularQtyCtrl.text,
    };
    return int.tryParse(raw.trim()) ?? 0;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_imageBytes == null) {
      setState(() => _error = 'Add a banner image — required for every event.');
      return;
    }
    if (_category == null) {
      setState(() => _error = 'Choose an event category.');
      return;
    }
    if (_listingType == 'ticketed' && _selectedStates.isEmpty) {
      setState(() => _error = 'Select at least one state for a ticketed event.');
      return;
    }
    if (!_formKey.currentState!.validate()) {
      setState(() => _error = 'Please fix the highlighted fields.');
      return;
    }

    // Ads Only listings may omit every location and schedule field. Ticketed
    // events still require a complete future schedule for each selected state.
    if (_listingType == 'ticketed' && _customizeDatesPerState) {
      for (final state in _selectedStates) {
        final date = _locationDates[state];
        final time = _locationTimes[state];
        if (date == null || time == null) {
          setState(() => _error = 'Choose a date and time for $state.');
          return;
        }
        final scheduled = DateTime(
          date.year, date.month, date.day, time.hour, time.minute,
        );
        if (!scheduled.isAfter(DateTime.now())) {
          setState(() => _error = 'The date and time for $state must be in the future.');
          return;
        }
      }
    } else if (_listingType == 'ticketed') {
      if (_date == null || _time == null) {
        setState(() => _error = 'Choose the event date and start time.');
        return;
      }
      final scheduled = DateTime(
        _date!.year, _date!.month, _date!.day, _time!.hour, _time!.minute,
      );
      if (!scheduled.isAfter(DateTime.now())) {
        setState(() => _error = 'Event date and time must be in the future.');
        return;
      }
    } else {
      // If an optional Ads Only schedule is supplied, reject it only when the
      // complete date/time is already in the past. Partial/empty values are OK.
      if (!_customizeDatesPerState && _date != null && _time != null) {
        final scheduled = DateTime(
          _date!.year, _date!.month, _date!.day, _time!.hour, _time!.minute,
        );
        if (!scheduled.isAfter(DateTime.now())) {
          setState(() => _error = 'Event date and time must be in the future.');
          return;
        }
      }
      if (_customizeDatesPerState) {
        for (final state in _selectedStates) {
          final date = _locationDates[state];
          final time = _locationTimes[state];
          if (date == null || time == null) continue;
          final scheduled = DateTime(
            date.year, date.month, date.day, time.hour, time.minute,
          );
          if (!scheduled.isAfter(DateTime.now())) {
            setState(() => _error = 'The date and time for $state must be in the future.');
            return;
          }
        }
      }
    }

    if (_listingType == 'ticketed' && _tiers.isEmpty) {
      setState(() => _error = 'Choose at least one ticket tier.');
      return;
    }
    if (_listingType == 'ticketed' &&
        _tiers.any((tier) => _tierPrice(tier) <= 0)) {
      setState(() => _error = 'Enter a price above zero for each ticket tier.');
      return;
    }
    if (_listingType == 'ticketed' &&
        _tiers.any((tier) => _tierQuantity(tier) <= 0)) {
      setState(() => _error = 'Enter a positive quantity for every selected ticket tier.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    int? createdEventId;
    try {
      final tierList = _listingType == 'ticketed'
          ? _tiers.toList()
          : <String>[];
      final basePrice = _listingType == 'ads_only'
          ? 0.0
          : tierList.map(_tierPrice).reduce((a, b) => a < b ? a : b);

      final locationEntries = <Map<String, String>>[];
      for (final state in _selectedStates) {
        final address = _selectedStates.length == 1
            ? _addressCtrl.text.trim()
            : (_locationAddressCtrls[state]?.text.trim() ?? '');

        final entry = <String, String>{
          'state': state,
          'address': address,
        };

        if (_customizeDatesPerState) {
          final date = _locationDates[state];
          final time = _locationTimes[state];
          if (date != null) {
            entry['date'] = DateFormat('yyyy-MM-dd').format(date);
          }
          if (time != null) {
            entry['time'] =
                '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
          }
        }
        locationEntries.add(entry);
      }

      DateTime? canonicalWhen;
      if (_customizeDatesPerState) {
        final schedules = _selectedStates
            .where((state) =>
                _locationDates[state] != null && _locationTimes[state] != null)
            .map((state) {
          final date = _locationDates[state]!;
          final time = _locationTimes[state]!;
          return DateTime(
            date.year, date.month, date.day, time.hour, time.minute,
          );
        }).toList()
          ..sort((a, b) => a.compareTo(b));
        if (schedules.isNotEmpty) canonicalWhen = schedules.first;
      } else if (_date != null && _time != null) {
        canonicalWhen = DateTime(
          _date!.year, _date!.month, _date!.day,
          _time!.hour, _time!.minute,
        );
      }

      final dateText = _customizeDatesPerState
          ? (canonicalWhen == null
              ? ''
              : DateFormat('yyyy-MM-dd').format(canonicalWhen))
          : (_date == null ? '' : DateFormat('yyyy-MM-dd').format(_date!));
      final timeText = _customizeDatesPerState
          ? (canonicalWhen == null
              ? ''
              : '${canonicalWhen.hour.toString().padLeft(2, '0')}:${canonicalWhen.minute.toString().padLeft(2, '0')}')
          : (_time == null
              ? ''
              : '${_time!.hour.toString().padLeft(2, '0')}:${_time!.minute.toString().padLeft(2, '0')}');
      final canonicalAddress = _addressCtrl.text.trim().isNotEmpty
          ? _addressCtrl.text.trim()
          : (locationEntries.isNotEmpty
              ? (locationEntries.first['address'] ?? '')
              : '');

      final form = FormData();
      void field(String key, String value) =>
          form.fields.add(MapEntry(key, value));

      field('event_name', _nameCtrl.text.trim());
      field('event_type', _category!);
      field('listing_type', _listingType);
      if (_listingType == 'ticketed') {
        field('capacity_tier', _capacityTier);
      }
      field('description', _descriptionCtrl.text.trim());
      field('event_date', dateText);
      field('event_time', timeText);
      field('phone_contact_1', _phoneCtrl.text.trim());
      if (_phone2Ctrl.text.trim().isNotEmpty) {
        field('phone_contact_2', _phone2Ctrl.text.trim());
      }
      field('state', _selectedStates.join(','));
      field('address', canonicalAddress);
      field('visibility', _selectedStates.isEmpty ? 'all states' : 'specific state');
      field('event_visibility', _privateEvent ? 'private' : 'public');
      field('price', basePrice.toStringAsFixed(2));
      field('ticket_type', tierList.join(','));
      field('ticket_type_mode', tierList.join(','));
      field('status', 'draft');
      field('locations_json', jsonEncode(locationEntries));
      if (_listingType == 'ticketed') {
        field('regular_price', _tierPrice('regular').toStringAsFixed(2));
        if (_tiers.contains('vip')) {
          field('vip_price', _tierPrice('vip').toStringAsFixed(2));
        }
        if (_tiers.contains('premium')) {
          field('premium_price', _tierPrice('premium').toStringAsFixed(2));
        }
        if (_regularQtyCtrl.text.trim().isNotEmpty) {
          field('regular_quantity', _regularQtyCtrl.text.trim());
        }
        if (_vipQtyCtrl.text.trim().isNotEmpty) {
          field('vip_quantity', _vipQtyCtrl.text.trim());
        }
        if (_premiumQtyCtrl.text.trim().isNotEmpty) {
          field('premium_quantity', _premiumQtyCtrl.text.trim());
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
      createdEventId = eventId;
      if (eventId <= 0) {
        throw Exception('The event was created but its ID was not returned. Please contact support before retrying.');
      }

      final payment = await ClientApiService.initializeListingFeePayment(eventId);
      ClientApiService.pendingListingFeeEventId = eventId;
      final checkoutUri = Uri.tryParse(
        payment['authorization_url'].toString(),
      );
      if (checkoutUri == null ||
          (checkoutUri.scheme != 'https' && checkoutUri.scheme != 'http')) {
        throw Exception('Paystack returned an invalid checkout address.');
      }

      final opened = await launchUrl(
        checkoutUri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        throw Exception('Could not open Paystack checkout. Your event is saved as a draft; do not create it again.');
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      if (createdEventId != null && createdEventId > 0) {
        // The draft already exists. Close the form so a retry cannot create a
        // second event; the organizer can retry payment from the event details.
        Navigator.pop(context, true);
        return;
      }
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
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
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
                        'Create event ad',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Publish to the app and website instantly.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMuted,
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
                  GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      height: 168,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFFE2E8F0),
                          width: 1.5,
                        ),
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
                                  'Upload event banner *',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'JPG, PNG or WebP up to 10 MB',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textMuted,
                                  ),
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
                                      color: Colors.black.withValues(
                                        alpha: 0.55,
                                      ),
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
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r"[A-Za-zÀ-ÖØ-öø-ÿ'. -]"),
                      ),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Event name *',
                      hintText: 'e.g. Lagos Summer Concert',
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
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _category,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Category *'),
                    items: _categories
                        .map(
                          (category) => DropdownMenuItem(
                            value: category,
                            child: Text(category),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _category = value),
                    validator: (value) =>
                        value == null ? 'Choose a category' : null,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _listingType,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Listing type *',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'ads_only',
                        child: Text('Ads Only — advertisement without tickets'),
                      ),
                      DropdownMenuItem(
                        value: 'ticketed',
                        child: Text('Ads with Events & Ticketing'),
                      ),
                    ],
                    onChanged: _submitting
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() {
                              _listingType = value;
                              _error = null;
                            });
                          },
                  ),
                  if (_listingType == 'ticketed') ...[
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: _capacityTier,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Total ticket capacity *',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: '0-100',
                          child: Text('1–100 tickets — ₦1,000 listing fee'),
                        ),
                        DropdownMenuItem(
                          value: '101-250',
                          child: Text('101–250 tickets — ₦1,500 listing fee'),
                        ),
                        DropdownMenuItem(
                          value: '251-500',
                          child: Text('251–500 tickets — ₦2,000 listing fee'),
                        ),
                        DropdownMenuItem(
                          value: '501-1000',
                          child: Text('501–1,000 tickets — ₦2,500 listing fee'),
                        ),
                        DropdownMenuItem(
                          value: '1001-unlimited',
                          child: Text('1,001+ tickets — ₦3,000 listing fee'),
                        ),
                      ],
                      onChanged: _submitting
                          ? null
                          : (value) {
                              if (value == null) return;
                              setState(() {
                                _capacityTier = value;
                                _error = null;
                              });
                            },
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'The selected capacity must match the combined quantities of your ticket tiers.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _descriptionCtrl,
                    maxLines: 4,
                    maxLength: 600,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Description *',
                      alignLabelWithHint: true,
                      hintText: 'What should attendees expect?',
                    ),
                    validator: (value) => (value?.trim().isEmpty ?? true)
                        ? 'Description is required'
                        : null,
                  ),
                  if (!_customizeDatesPerState) ...[
                    Row(
                      children: [
                        Expanded(
                          child: _pickerTile(
                            label: _listingType == 'ticketed' ? 'Date *' : 'Date (optional)',
                            value: _date == null
                                ? 'Select date'
                                : DateFormat('MMM d, yyyy').format(_date!),
                            icon: Icons.calendar_today_outlined,
                            onTap: _pickDate,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _pickerTile(
                            label: _listingType == 'ticketed' ? 'Start time *' : 'Start time (optional)',
                            value: _time == null
                                ? 'Select time'
                                : _time!.format(context),
                            icon: Icons.schedule,
                            onTap: _pickTime,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _chooseStates,
                      icon: const Icon(Icons.location_on_outlined),
                      label: Text(
                        _selectedStates.isEmpty
                            ? (_listingType == 'ticketed' ? 'Select state(s) *' : 'Select state(s) (optional)')
                            : '${_selectedStates.length} state(s) selected',
                      ),
                    ),
                  ),
                  if (_selectedStates.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _selectedStates.map((state) {
                        return Chip(
                          label: Text(state),
                          onDeleted: () {
                            setState(() {
                              _selectedStates.remove(state);
                              _locationAddressCtrls.remove(state)?.dispose();
                              _locationDates.remove(state);
                              _locationTimes.remove(state);
                              if (_selectedStates.length < 2) {
                                _customizeDatesPerState = false;
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _addressCtrl,
                    maxLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: _listingType == 'ads_only'
                          ? 'Venue address (optional)'
                          : (_selectedStates.length > 1
                              ? 'Main venue address (optional)'
                              : 'Venue address *'),
                      alignLabelWithHint: true,
                      hintText: 'Street, landmark, city',
                    ),
                    validator: (value) {
                      if (_listingType == 'ads_only' || _selectedStates.length > 1) {
                        return null;
                      }
                      return (value?.trim().isEmpty ?? true)
                          ? 'Address is required'
                          : null;
                    },
                  ),
                  if (_selectedStates.length > 1) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Address for each state',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    for (final state in _selectedStates) ...[
                      TextFormField(
                        key: ValueKey('location-address-$state'),
                        controller: _locationAddressCtrls[state],
                        maxLines: 2,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          labelText: _listingType == 'ticketed' ? '$state address *' : '$state address (optional)',
                          hintText: 'Street, landmark, city',
                        ),
                        validator: (value) => _listingType == 'ads_only'
                            ? null
                            : ((value?.trim().isEmpty ?? true)
                                ? 'Enter the venue address for $state'
                                : null),
                      ),
                      const SizedBox(height: 10),
                    ],
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Use different dates & times per state',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'Otherwise, all selected states share the event date and time.',
                        style: TextStyle(fontSize: 12),
                      ),
                      value: _customizeDatesPerState,
                      onChanged: (value) => setState(() {
                        _customizeDatesPerState = value;
                      }),
                    ),
                    if (_customizeDatesPerState)
                      for (final state in _selectedStates) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFFEAEEF2),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                state,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: _pickerTile(
                                      label: _listingType == 'ticketed' ? 'Date *' : 'Date (optional)',
                                      value: _locationDates[state] == null
                                          ? 'Select date'
                                          : DateFormat('MMM d, yyyy').format(
                                              _locationDates[state]!,
                                            ),
                                      icon: Icons.calendar_today_outlined,
                                      onTap: () => _pickLocationDate(state),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _pickerTile(
                                      label: _listingType == 'ticketed' ? 'Time *' : 'Time (optional)',
                                      value: _locationTimes[state] == null
                                          ? 'Select time'
                                          : _locationTimes[state]!.format(context),
                                      icon: Icons.schedule,
                                      onTap: () => _pickLocationTime(state),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                  ],
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Primary contact *',
                      hintText: '+2348012345678',
                    ),
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.isEmpty) return 'Primary contact is required';
                      if (!_phoneRule.hasMatch(text)) {
                        return 'Enter a valid phone number';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _phone2Ctrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Secondary contact (optional)',
                    ),
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.isEmpty) return null;
                      return _phoneRule.hasMatch(text)
                          ? null
                          : 'Enter a valid phone number';
                    },
                  ),
                  const SizedBox(height: 8),
                  if (_listingType == 'ticketed') ...[
                    const SizedBox(height: 4),
                    const Text(
                      'Ticket tiers',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: ['regular', 'vip', 'premium'].map((tier) {
                        final selected = _tiers.contains(tier);
                        return ChoiceChip(
                          label: Text(_tierLabel(tier)),
                          selected: selected,
                          checkmarkColor: Colors.white,
                          labelStyle: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: selected ? Colors.white : AppTheme.textMuted,
                          ),
                          selectedColor: AppTheme.primary,
                          backgroundColor: Colors.white,
                          side: BorderSide(
                            color: selected
                                ? AppTheme.primary
                                : const Color(0xFFE2E8F0),
                          ),
                          onSelected: (value) {
                            setState(() {
                              if (value) {
                                _tiers.add(tier);
                              } else {
                                _tiers.remove(tier);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 10),
                    for (final tier in ['regular', 'vip', 'premium'])
                      if (_tiers.contains(tier)) ...[
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextFormField(
                                controller: switch (tier) {
                                  'vip' => _vipPriceCtrl,
                                  'premium' => _premiumPriceCtrl,
                                  _ => _regularPriceCtrl,
                                },
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: InputDecoration(
                                  labelText: '${_tierLabel(tier)} price (₦) *',
                                ),
                                validator: (value) {
                                  final price = double.tryParse(
                                    value?.trim() ?? '',
                                  );
                                  if (price == null || price <= 0) {
                                    return 'Enter a price';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: switch (tier) {
                                  'vip' => _vipQtyCtrl,
                                  'premium' => _premiumQtyCtrl,
                                  _ => _regularQtyCtrl,
                                },
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Qty',
                                  hintText: 'No limit',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                  ],
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Private event',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text(
                      'Only people with the share link can find it.',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: _privateEvent,
                    onChanged: (value) => setState(() => _privateEvent = value),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
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
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _privateEvent
                                  ? 'Create private event'
                                  : 'Save event draft',
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pickerTile({
    required String label,
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
          border: Border.all(color: const Color(0xFFEAEEF2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(icon, size: 16, color: AppTheme.primary),
                const SizedBox(width: 6),
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
          ],
        ),
      ),
    );
  }
}
