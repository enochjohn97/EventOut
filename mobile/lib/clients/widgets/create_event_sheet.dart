import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
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
  final _capacityCtrl = TextEditingController();
  final _regularPriceCtrl = TextEditingController();
  final _vipPriceCtrl = TextEditingController();
  final _premiumPriceCtrl = TextEditingController();
  final _regularQtyCtrl = TextEditingController();
  final _vipQtyCtrl = TextEditingController();
  final _premiumQtyCtrl = TextEditingController();

  Uint8List? _imageBytes;
  String? _imageName;
  String? _category;
  String? _state;
  DateTime? _date;
  TimeOfDay? _time;
  bool _free = false;
  bool _publishNow = false;
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
      _capacityCtrl,
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
    if (_state == null || _category == null) {
      setState(() => _error = 'Choose a category and state.');
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
    if (!_free && _tiers.isEmpty) {
      setState(() => _error = 'Choose at least one ticket tier.');
      return;
    }
    if (!_free && _tiers.any((tier) => _tierPrice(tier) <= 0)) {
      setState(() => _error = 'Enter a price above zero for each ticket tier.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final dateText = DateFormat('yyyy-MM-dd').format(when);
      final timeText =
          '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
      final tierList = _tiers.toList();
      final basePrice = _free
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
      field('state', _state!);
      field('address', _addressCtrl.text.trim());
      field('visibility', 'specific state');
      field('event_visibility', _privateEvent ? 'private' : 'public');
      field('price', basePrice.toStringAsFixed(2));
      field('ticket_type', tierList.join(','));
      field('ticket_type_mode', tierList.join(','));
      field('status', _publishNow ? 'published' : 'draft');
      field(
        'locations_json',
        jsonEncode([
          {'state': _state, 'address': _addressCtrl.text.trim()},
        ]),
      );
      if (_free) field('is_free', '1');
      if (_capacityCtrl.text.trim().isNotEmpty) {
        field('max_capacity', _capacityCtrl.text.trim());
      }
      if (!_free) {
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

      await ClientApiService.createEvent(form);
      if (!mounted) return;
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
                  Row(
                    children: [
                      Expanded(
                        child: _pickerTile(
                          label: 'Date *',
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
                          label: 'Start time *',
                          value: _time == null
                              ? 'Select time'
                              : _time!.format(context),
                          icon: Icons.schedule,
                          onTap: _pickTime,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _state,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'State *'),
                    items: _states
                        .map(
                          (state) => DropdownMenuItem(
                            value: state,
                            child: Text(state),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _state = value),
                    validator: (value) =>
                        value == null ? 'Choose a state' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _addressCtrl,
                    maxLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Venue address *',
                      alignLabelWithHint: true,
                      hintText: 'Street, landmark, city',
                    ),
                    validator: (value) => (value?.trim().isEmpty ?? true)
                        ? 'Address is required'
                        : null,
                  ),
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
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Free event',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text(
                      'Attendees claim tickets at no cost.',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: _free,
                    onChanged: (value) => setState(() => _free = value),
                  ),
                  if (!_free) ...[
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
                                  if (_free) return null;
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
                  TextFormField(
                    controller: _capacityCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Max capacity (optional)',
                      hintText: 'Total tickets available',
                    ),
                  ),
                  const SizedBox(height: 8),
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
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Publish immediately',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text(
                      'Off keeps it as a draft you can finish later.',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: _publishNow,
                    onChanged: (value) => setState(() => _publishNow = value),
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
                              _publishNow
                                  ? 'Publish event'
                                  : 'Save event draft',
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Paid events are processed by your connected Paystack account. '
                    'The platform commission applies to each successful payment.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textMuted,
                      height: 1.4,
                    ),
                  ),
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
