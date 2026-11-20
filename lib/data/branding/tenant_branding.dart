// dart format width=100
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/dio_client.dart';

/// The tenant identity the app shows: logo and company name from `GET /api/branding`.
///
/// The primary colour is deliberately not read here: `AppColors.Y` is hardcoded across the app, so
/// a per-tenant colour needs its own pass over those call sites (see the web shell for the colour
/// side of this feature).
class TenantBranding {
  const TenantBranding({this.logoUrl, this.companyName});

  final String? logoUrl;
  final String? companyName;

  bool get isEmpty => logoUrl == null && companyName == null;

  factory TenantBranding.fromJson(Map<String, dynamic> json) => TenantBranding(
    logoUrl: _clean(json['logoUrl']),
    companyName: _clean(json['companyName']),
  );

  Map<String, dynamic> toJson() => {'logoUrl': logoUrl, 'companyName': companyName};

  static String? _clean(Object? v) {
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  /// Only an absolute http(s) URL is worth handing to an image loader; anything else (a relative
  /// path the tenant typed, `javascript:`, a data URI) would just fail or be unwanted.
  static bool isLoadableUrl(String? url) {
    if (url == null) return false;
    final uri = Uri.tryParse(url);
    return uri != null && uri.hasAuthority && (uri.scheme == 'https' || uri.scheme == 'http');
  }
}

const _cacheKey = 'tenant_branding_v1';

/// Reads the last branding from disk and fetches the current one. Never throws: branding is
/// decoration, so every failure (offline, 4xx, bad JSON, missing plugin) degrades to "no branding".
class TenantBrandingRepository {
  TenantBrandingRepository(this._dio);

  final Dio _dio;

  Future<TenantBranding?> readCached() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_cacheKey);
      if (raw == null) return null;
      return TenantBranding.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<TenantBranding?> fetch() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/api/branding');
      final data = response.data;
      if (data == null) return null;
      final branding = TenantBranding.fromJson(data);
      await (await SharedPreferences.getInstance()).setString(_cacheKey, jsonEncode(branding.toJson()));
      return branding;
    } catch (_) {
      return null;
    }
  }
}

/// Cached branding first (so the logo is there offline and on a cold start), then the fresh one.
/// The cache lives in SharedPreferences, which the session ender clears on sign-out, so one
/// tenant's logo never shows for the next user.
final tenantBrandingProvider = StreamProvider<TenantBranding?>((ref) async* {
  TenantBrandingRepository repo;
  try {
    repo = TenantBrandingRepository(ref.watch(dioProvider));
  } catch (_) {
    yield null;
    return;
  }
  final cached = await repo.readCached();
  if (cached != null) yield cached;
  final fresh = await repo.fetch();
  if (fresh != null) yield fresh;
  if (cached == null && fresh == null) yield null;
});
