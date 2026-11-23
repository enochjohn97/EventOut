import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/adaptive_dialogs.dart';
import '../models/client_model.dart';
import '../providers/client_auth_provider.dart';
import '../providers/client_data_provider.dart';
import '../widgets/client_ui.dart';

const _states = [
  'Abia',
  'Adamawa',
  'Akwa Ibom',
  'Anambra',
  'Bauchi',
  'Bayelsa',
  'Benue',
  'Borno',
  'Cross River',
  'Delta',
  'Ebonyi',
  'Edo',
  'Ekiti',
  'Enugu',
  'FCT',
  'Gombe',
  'Imo',
  'Jigawa',
  'Kaduna',
  'Kano',
  'Katsina',
  'Kebbi',
  'Kogi',
  'Kwara',
  'Lagos',
  'Nasarawa',
  'Niger',
  'Ogun',
  'Ondo',
  'Osun',
  'Oyo',
  'Plateau',
  'Rivers',
  'Sokoto',
  'Taraba',
  'Yobe',
  'Zamfara',
];

class ClientProfileScreen extends StatefulWidget {
  const ClientProfileScreen({super.key});

  @override
  State<ClientProfileScreen> createState() => _ClientProfileScreenState();
}

class _ClientProfileScreenState extends State<ClientProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _businessCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _countryCtrl = TextEditingController();
  final _jobCtrl = TextEditingController();
  final _companyCtrl = TextEditingController();
  String? _state;
  bool _editing = false;
  bool _initialized = false;
  final Map<String, String> _kycFilePaths = {};
  double _kycUploadProgress = 0;

  static const _kycDocuments = <String, String>{
    'kyc_nin_file': 'NIN document',
    'kyc_voter_card_file': "Voter's card",
    'kyc_driver_license_file': "Driver's licence",
    'kyc_cac_file': 'CAC registration document',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = context.read<ClientAuthProvider>();
      await auth.refreshProfile();
      if (!mounted) return;
      setState(() => _sync(auth.client));
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _sync(context.read<ClientAuthProvider>().client);
      _initialized = true;
    }
  }

  void _sync(ClientModel? client) {
    _nameCtrl.text = client?.name ?? '';
    _businessCtrl.text = client?.businessName ?? '';
    _phoneCtrl.text = client?.phone ?? '';
    _addressCtrl.text = client?.address ?? '';
    _cityCtrl.text = client?.city ?? '';
    _countryCtrl.text = client?.country ?? 'Nigeria';
    _jobCtrl.text = client?.jobTitle ?? '';
    _companyCtrl.text = client?.company ?? '';
    _state = _states.contains(client?.state) ? client!.state : null;
  }

  @override
  void dispose() {
    for (final controller in [
      _nameCtrl,
      _businessCtrl,
      _phoneCtrl,
      _addressCtrl,
      _cityCtrl,
      _countryCtrl,
      _jobCtrl,
      _companyCtrl,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<ClientAuthProvider>();
    setState(() => _kycUploadProgress = 0);
    final ok = await auth.updateProfile(
      {
        'name': _nameCtrl.text,
        'business_name': _businessCtrl.text,
        'phone': _phoneCtrl.text,
        'address': _addressCtrl.text,
        'city': _cityCtrl.text,
        'state': _state ?? '',
        'country': _countryCtrl.text,
        'job_title': _jobCtrl.text,
        'company': _companyCtrl.text,
      },
      kycFilePaths: Map<String, String>.from(_kycFilePaths),
      onSendProgress: (sent, total) {
        if (!mounted || total <= 0) return;
        setState(() => _kycUploadProgress = sent / total);
      },
    );
    if (!mounted) return;
    if (ok) {
      setState(() {
        _kycFilePaths.clear();
        _kycUploadProgress = 0;
        _editing = false;
      });
      _toast('Profile updated and synced with the website.', AppTheme.success);
    } else {
      _toast(auth.error ?? 'Could not update your profile.', AppTheme.error);
    }
  }

  Future<void> _pickKycDocument(String field) async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      );

      if (file == null) return;
      final path = file.path;

      if (path == null || path.isEmpty) {
        _toast(
          'Could not access the selected file. Please choose it again.',
          AppTheme.error,
        );
        return;
      }

      final fileLength = await file.length();
      if (fileLength != null && fileLength > 2 * 1024 * 1024) {
        _toast(
          'This server currently accepts files up to 2 MB.',
          AppTheme.error,
        );
        return;
      }

      if (!mounted) return;
      setState(() => _kycFilePaths[field] = path);
    } catch (e) {
      if (mounted) {
        _toast('Could not select document: $e', AppTheme.error);
      }
    }
  }

  Widget _kycDocumentTile(String field, String label) {
    final path = _kycFilePaths[field];
    final filename = path?.replaceAll('\\', '/').split('/').last;

    return Card(
      child: ListTile(
        leading: const Icon(Icons.description_outlined),
        title: Text(label),
        subtitle: Text(
          filename ?? 'No document selected',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: TextButton(
          onPressed: context.read<ClientAuthProvider>().isLoading
              ? null
              : () => _pickKycDocument(field),
          child: Text(filename == null ? 'Choose' : 'Replace'),
        ),
      ),
    );
  }

  void _toast(String message, Color color) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showAdaptiveConfirm(
      context,
      title: 'Delete organizer account?',
      message:
          'This permanently deletes your client profile, events, tickets and '
          'payment records. Attendee tickets for your events stop working. '
          'This cannot be undone.',
      confirm: 'Delete permanently',
      isDestructive: true,
    );
    if (confirmed != true || !mounted) return;
    final auth = context.read<ClientAuthProvider>();
    final ok = await auth.deleteAccount();
    if (!mounted) return;
    if (!ok) {
      _toast(auth.error ?? 'Could not delete your account.', AppTheme.error);
      return;
    }
    context.read<ClientDataProvider>().reset();
    context.go('/client/login');
    _toast('Your account has been deleted.', AppTheme.success);
  }

  Future<void> _logout() async {
    final confirmed = await showAdaptiveConfirm(
      context,
      title: 'Log out',
      message: 'Are you sure you want to log out of the client portal?',
      confirm: 'Log out',
      isDestructive: true,
    );
    if (confirmed != true || !mounted) return;
    context.read<ClientDataProvider>().reset();
    await context.read<ClientAuthProvider>().logout();
    if (mounted) context.go('/client/login');
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<ClientAuthProvider>();
    final client = auth.client;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Profile'),
        actions: [
          if (!_editing)
            IconButton(
              tooltip: 'Edit profile',
              onPressed: () => setState(() => _editing = true),
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
        children: [
          Center(
            child: Column(
              children: [
                ClientAvatar(
                  imagePath: client?.profilePic,
                  initials: client?.initials ?? 'C',
                  radius: 42,
                ),
                const SizedBox(height: 12),
                Text(
                  client?.displayName ?? 'Client',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  client?.email ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.textMuted,
                  ),
                ),
                if ((client?.customId ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    client!.customId!,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if ((client?.verificationStatus ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: client!.verificationStatus == 'verified'
                          ? AppTheme.success.withValues(alpha: 0.1)
                          : const Color(0xFFB45309).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      client.verificationStatus == 'verified'
                          ? 'Verified organizer'
                          : 'Verification pending',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: client.verificationStatus == 'verified'
                            ? AppTheme.success
                            : const Color(0xFFB45309),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 22),
          if (!_editing) _summary(client) else _editForm(auth),
          const SizedBox(height: 24),
          _sectionTitle('Account'),
          _linkTile(
            Icons.dashboard_outlined,
            'Portal home',
            onTap: () => context.go('/client/home'),
          ),
          _linkTile(
            Icons.privacy_tip_outlined,
            'Privacy Policy',
            onTap: () => context.push('/privacy'),
          ),
          _linkTile(
            Icons.description_outlined,
            'Terms & Conditions',
            onTap: () => context.push('/terms'),
          ),
          _linkTile(
            Icons.cookie_outlined,
            'Cookie Policy',
            onTap: () => context.push('/cookies'),
          ),
          _linkTile(
            Icons.help_outline,
            'How account deletion works',
            onTap: () => context.push('/delete-data'),
          ),
          _linkTile(
            Icons.delete_outline,
            'Delete my account',
            onTap: _deleteAccount,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: auth.isLoading ? null : _logout,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.error,
                side: const BorderSide(color: AppTheme.error),
              ),
              child: const Text('Log out'),
            ),
          ),
          const SizedBox(height: 10),
          const Center(
            child: Text(
              'EventOut for Organizers · Powered by Attoneex Tech Solutions',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: AppTheme.textMuted,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _summary(ClientModel? client) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDEFF3)),
      ),
      child: Column(
        children: [
          _row('Business name', client?.businessName),
          _row('Contact name', client?.name),
          _row('Phone', client?.phone),
          _row('Email', client?.email),
          _row(
            'Location',
            [client?.city, client?.state, client?.country]
                .whereType<String>()
                .where((value) => value.trim().isNotEmpty)
                .join(', '),
          ),
          _row('Address', client?.address),
          _row('Job title', client?.jobTitle),
          _row('Company', client?.company),
        ],
      ),
    );
  }

  Widget _row(String label, String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: Text(
              text,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _editForm(ClientAuthProvider auth) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          TextFormField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Contact name *'),
            validator: (value) =>
                (value?.trim().isEmpty ?? true) ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _businessCtrl,
            decoration: const InputDecoration(labelText: 'Business name *'),
            validator: (value) =>
                (value?.trim().isEmpty ?? true) ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone',
              hintText: '08012345678',
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
              LengthLimitingTextInputFormatter(13),
            ],
            validator: (value) {
              final text = value?.trim() ?? '';
              if (text.isEmpty) return null;
              final digits = text.replaceAll(RegExp(r'\D'), '');
              if (!RegExp(
                r'^(0[789][01]\d{8}|234[789][01]\d{8})$',
              ).hasMatch(digits)) {
                return 'Enter a valid Nigerian phone number';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _jobCtrl,
            decoration: const InputDecoration(labelText: 'Job title'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _companyCtrl,
            decoration: const InputDecoration(labelText: 'Company'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _addressCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Address',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _cityCtrl,
            decoration: const InputDecoration(labelText: 'City'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _state,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'State'),
            items: _states
                .map(
                  (state) => DropdownMenuItem(value: state, child: Text(state)),
                )
                .toList(),
            onChanged: (value) => setState(() => _state = value),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _countryCtrl,
            readOnly: true,
            decoration: const InputDecoration(
              labelText: 'Country',
              suffixIcon: Icon(Icons.lock_outline, size: 16),
            ),
          ),
          const SizedBox(height: 18),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Identity documents (PDF or image, maximum 2 MB each)',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),
          ..._kycDocuments.entries.map(
            (entry) => _kycDocumentTile(entry.key, entry.value),
          ),
          if (auth.isLoading && _kycFilePaths.isNotEmpty) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: _kycUploadProgress > 0 ? _kycUploadProgress : null,
            ),
            const SizedBox(height: 4),
            Text(
              '${(_kycUploadProgress * 100).clamp(0, 100).toStringAsFixed(0)}% uploaded',
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: auth.isLoading ? null : _save,
              child: auth.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Save changes'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: auth.isLoading
                  ? null
                  : () => setState(() {
                      _sync(auth.client);
                      _kycFilePaths.clear();
                      _kycUploadProgress = 0;
                      _editing = false;
                    }),
              child: const Text('Cancel'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _linkTile(IconData icon, String label, {required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Icon(icon, size: 18, color: AppTheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppTheme.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
