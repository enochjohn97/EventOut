/// Profile of a signed-in EventOut client (organizer) account.
///
/// Mirrors the web client profile (`GET /client/auth/check-session`) so the
/// phone and the website always show the same business details.
class ClientModel {
  final int id; // auth_accounts.id
  final int? profileId; // clients.id
  final String name;
  final String businessName;
  final String email;
  final String? phone;
  final String? address;
  final String? city;
  final String? state;
  final String? country;
  final String? jobTitle;
  final String? company;
  final String? dob;
  final String? gender;
  final String? customId;
  final String? profilePic;
  final String? status;
  final String? verificationStatus;
  final String? token;

  const ClientModel({
    required this.id,
    this.profileId,
    required this.name,
    required this.businessName,
    required this.email,
    this.phone,
    this.address,
    this.city,
    this.state,
    this.country,
    this.jobTitle,
    this.company,
    this.dob,
    this.gender,
    this.customId,
    this.profilePic,
    this.status,
    this.verificationStatus,
    this.token,
  });

  String get displayName =>
      businessName.trim().isNotEmpty ? businessName.trim() : name.trim();

  String get initials {
    final source = displayName.trim();
    if (source.isEmpty) return 'C';
    final parts = source.split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  factory ClientModel.fromJson(Map<String, dynamic> json) {
    return ClientModel(
      // check-session returns the auth id in `id`; verify-otp returns it too.
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      profileId: int.tryParse(
        (json['profile_id'] ?? json['client_id'])?.toString() ?? '',
      ),
      name: (json['name'] ?? '').toString(),
      businessName: (json['business_name'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      phone: json['phone']?.toString(),
      address: json['address']?.toString(),
      city: json['city']?.toString(),
      state: json['state']?.toString(),
      country: json['country']?.toString(),
      jobTitle: json['job_title']?.toString(),
      company: json['company']?.toString(),
      dob: json['dob']?.toString(),
      gender: json['gender']?.toString(),
      customId: json['custom_id']?.toString(),
      profilePic:
          json['profile_pic']?.toString() ?? json['profile_image']?.toString(),
      status: json['status']?.toString(),
      verificationStatus: json['verification_status']?.toString(),
      token: json['token']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'profile_id': profileId,
    'name': name,
    'business_name': businessName,
    'email': email,
    'phone': phone,
    'address': address,
    'city': city,
    'state': state,
    'country': country,
    'job_title': jobTitle,
    'company': company,
    'dob': dob,
    'gender': gender,
    'custom_id': customId,
    'profile_pic': profilePic,
    'status': status,
    'verification_status': verificationStatus,
  };

  ClientModel copyWith({
    String? name,
    String? businessName,
    String? phone,
    String? address,
    String? city,
    String? state,
    String? country,
    String? jobTitle,
    String? company,
    String? dob,
    String? gender,
    String? profilePic,
    String? token,
  }) {
    return ClientModel(
      id: id,
      profileId: profileId,
      name: name ?? this.name,
      businessName: businessName ?? this.businessName,
      email: email,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      city: city ?? this.city,
      state: state ?? this.state,
      country: country ?? this.country,
      jobTitle: jobTitle ?? this.jobTitle,
      company: company ?? this.company,
      dob: dob ?? this.dob,
      gender: gender ?? this.gender,
      customId: customId,
      profilePic: profilePic ?? this.profilePic,
      status: status,
      verificationStatus: verificationStatus,
      token: token ?? this.token,
    );
  }
}
