// 雲端模式(Supabase Auth)的登入 seam。寫法對齊
// ~/Documents/self/accounting 的 `lib/data/auth.dart`(signInWithIdToken + nonce)。
//
// 抽成 [CloudAuthService] 介面的理由:SessionController 的雲端分支要能在
// `flutter test` 裡不連網驗證(登入成功 userId = auth uid、恢復 session、
// 登出),測試以 [cloudAuthServiceProvider] override 成假件即可。
//
// [cloudAuthServiceProvider] 為 null = 非雲端模式(USE_MOCK、測試、未設定
// Supabase),SessionController 走原本的本機登入行為;非 null 才走 Supabase。
// 切換點跟資料層一樣看 [supabaseClientProvider](見 data/supabase_client.dart)。
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent, OAuthProvider, SupabaseClient;

import '../../data/supabase_client.dart';

/// Supabase 登入者(只留 session 需要的欄位)。
class CloudAuthUser {
  const CloudAuthUser({required this.id, this.email});

  /// Supabase auth uid(= `public.users.id`,RLS 的擁有者)。
  final String id;
  final String? email;
}

/// Apple 登入成功的結果:Supabase 登入者 + Apple 這次給的姓名/信箱
/// (Apple 只在該 Apple ID 首次授權本 App 時給姓名,之後都是 null)。
class CloudAppleSignInResult {
  const CloudAppleSignInResult({
    required this.user,
    this.givenName,
    this.familyName,
    this.appleEmail,
  });

  final CloudAuthUser user;
  final String? givenName;
  final String? familyName;
  final String? appleEmail;
}

/// 這個平台能不能走原生 Sign in with Apple(iOS/macOS)。Web/Android 沒有
/// 原生管道,雲端模式下登入頁給提示而不是呼叫(Google 登入之後補)。
bool get isNativeAppleSignInAvailable =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS);

/// 抽成 provider 讓 widget 測試可覆寫平台條件(`flutter test` host 不是 iOS)。
final nativeAppleSignInAvailableProvider = Provider<bool>((ref) => isNativeAppleSignInAvailable);

abstract interface class CloudAuthService {
  /// 目前的 Supabase session 登入者(App 重啟後由 supabase_flutter 從本機
  /// 儲存恢復);沒有 session 為 null。
  CloudAuthUser? get currentUser;

  /// 原生 Apple 登入 → `signInWithIdToken`。使用者取消時讓
  /// [SignInWithAppleAuthorizationException](code = canceled)原樣拋出,
  /// 由呼叫端決定靜默處理;其他失敗一律拋例外。
  Future<CloudAppleSignInResult> signInWithApple();

  Future<void> signOut();
}

class SupabaseCloudAuthService implements CloudAuthService {
  SupabaseCloudAuthService(this._client);

  final SupabaseClient _client;

  @override
  CloudAuthUser? get currentUser {
    final u = _client.auth.currentUser;
    return u == null ? null : CloudAuthUser(id: u.id, email: u.email);
  }

  /// nonce 防重放:原文交給 Supabase 驗、SHA-256 雜湊交給 Apple 簽進 id token。
  @override
  Future<CloudAppleSignInResult> signInWithApple() async {
    if (!isNativeAppleSignInAvailable) {
      throw UnsupportedError('此平台沒有原生 Sign in with Apple');
    }
    final rawNonce = _rawNonce();
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: sha256.convert(utf8.encode(rawNonce)).toString(),
    );
    final idToken = credential.identityToken;
    if (idToken == null || idToken.isEmpty) {
      throw StateError('Apple 登入沒有回傳 identityToken');
    }
    final response = await _client.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );
    final user = response.user ?? _client.auth.currentUser;
    if (user == null) {
      throw StateError('Supabase signInWithIdToken 沒有回傳登入者');
    }
    return CloudAppleSignInResult(
      user: CloudAuthUser(id: user.id, email: user.email),
      givenName: credential.givenName,
      familyName: credential.familyName,
      appleEmail: credential.email,
    );
  }

  static String _rawNonce() {
    final rand = Random.secure();
    return base64UrlEncode(List<int>.generate(32, (_) => rand.nextInt(256))).replaceAll('=', '');
  }

  @override
  Future<void> signOut() => _client.auth.signOut();
}

/// null = 非雲端模式(見檔頭)。
final cloudAuthServiceProvider = Provider<CloudAuthService?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabaseCloudAuthService(client);
});

/// Supabase 端 session 結束事件:token refresh 失敗、遠端登出、帳號被刪等,
/// supabase_flutter 都會發 [AuthChangeEvent.signedOut]。SessionController 監聽它,
/// 把本機登入態一併收掉,不必等 repository 報「需要登入」才察覺。
/// 非雲端模式(含測試預設)為空 stream。每次事件帶不同時間戳,確保連續事件
/// 都會通知 listener。
final cloudSessionEndedProvider = StreamProvider<DateTime>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const Stream<DateTime>.empty();
  return client.auth.onAuthStateChange
      .where((s) => s.event == AuthChangeEvent.signedOut)
      .map((_) => DateTime.now());
});
