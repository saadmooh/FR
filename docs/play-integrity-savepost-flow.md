# تدفق التحقق من Play Integrity عند حفظ منشور (SavePost)

## نظرة عامة

عند محاولة المستخدم حفظ منشور عبر `SavePostSheet`، يتم تنفيذ سلسلة من عمليات التحقق الأمنية قبل إرسال الطلب للـ AI Proxy. يوضح هذا المستند ترتيب العمل المعمول به.

---

## ترتيب خطوات التحقق (من العميل إلى الخادم)

### 1. **التحقق من المصادقة (Supabase Auth) - من جانب العميل**
**ملف**: `lib/services/ai_proxy_service.dart` (السطور 39-80)

```dart
// التحقق من وجود جلسة Supabase صالحة
final session = client.auth.currentSession;
if (session == null) {
  // محاولة تحديث الجلسة من Firebase
  final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
  if (firebaseUser != null) {
    final idToken = await firebaseUser.getIdToken();
    await client.auth.signInWithIdToken(
      provider: OAuthProvider('custom:firebase'),
      idToken: idToken,
    );
  }
}
if (session == null) {
  throw AiProxyException(401, 'UNAUTHENTICATED', 'يجب تسجيل الدخول أولاً');
}
```

**النتيجة**: يجب أن يكون المستخدم مسجل الدخول بجلسة صالحة.

---

### 2. **توليد Nonce - من جانب العميل**
**ملف**: `lib/services/integrity_service.dart` (السطور 26-31)

```dart
String generateNonce(String prompt) {
  final random = Random.secure();
  final salt = List<int>.generate(16, (_) => random.nextInt(256));
  final hash = sha256.convert([...utf8.encode(prompt), ...salt]);
  return base64UrlEncode(hash.bytes);
}
```

**الاستخدام**: يتم استدعاؤها في `AiProxyService.sendPrompt()` السطر 82:
```dart
final nonce = _integrity.generateNonce(prompt);
```

**الغرض**: ربط رمز النزاهة (Integrity Token) بالطلب المحدد لمنع هجمات إعادة التشغيل (Replay Attacks).

---

### 3. **طلب رمز النزاهة (Integrity Token) من Google Play - من جانب العميل**
**ملف**: `lib/services/integrity_service.dart` (السطور 33-61)

```dart
Future<String> requestIntegrityToken({required String nonce}) async {
  if (!enabled || cloudProjectNumber <= 0) {
    throw IntegrityException('INTEGRITY_DISABLED', 'Play Integrity is not configured');
  }
  try {
    final token = await _wrapper.requestIntegrityToken(
      cloudProjectNumber: cloudProjectNumber.toString(),
      nonce: nonce,
    );
    if (token == null || token.isEmpty) {
      throw IntegrityException('EMPTY_TOKEN', 'Empty integrity token');
    }
    return token;
  } on PlayIntegrityException catch (e) {
    throw IntegrityException(e.code, e.message);
  }
}
```

**الشروط**:
- يجب أن يكون `enabled = true` و `cloudProjectNumber > 0`
- يستخدم `flutter_play_integrity_wrapper` للتواصل مع Google Play Services

**النتيجة**: رمز نزاهة (JWT) موقع من Google، يحتوي على:
- `requestDetails.requestHash` (هاش الـ nonce)
- `appIntegrity.appRecognitionVerdict` (يجب أن يكون `PLAY_RECOGNIZED`)
- `appIntegrity.packageName` (يجب أن يطابق `EXPECTED_PACKAGE_NAME`)
- `deviceIntegrity.deviceRecognitionVerdict` (يجب أن يتضمن `MEETS_DEVICE_INTEGRITY`)
- `requestDetails.timestampMillis` (للتحقق من الحداثة)

---

### 4. **إرسال الطلب للـ AI Proxy مع encabezados النزاهة - من جانب العميل**
**ملف**: `lib/services/ai_proxy_service.dart` (السطور 99-112)

```dart
final body = <String, dynamic>{'prompt': prompt, ...};
final headers = <String, String>{};

if (integrityToken != null && !integrityFailed) {
  headers['X-Integrity-Token'] = integrityToken;
  headers['X-Request-Nonce'] = nonce;
}

// السماح بتجاوز النزاهة في debug builds
if (!strictIntegrityCheck) {
  headers['X-Debug-Build'] = 'true';
}
```

---

### 5. **التحقق من Supabase Auth - من جانب الخادم (Edge Function)**
**ملف**: `supabase/functions/ai-proxy/index.ts` (السطور 319-331)

```typescript
const authHeader = req.headers.get('Authorization') ?? '';
const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  global: { headers: { Authorization: authHeader } },
});
const { data: { user }, error: authError } = await supabase.auth.getUser();

if (authError || !user) {
  return jsonError(401, 'UNAUTHENTICATED', 'You must be signed in first');
}
```

---

### 6. **التحقق من Play Integrity - من جانب الخادم (Edge Function)**
**ملف**: `supabase/functions/ai-proxy/index.ts` (السطور 333-363)

```typescript
const integrityToken = req.headers.get('X-Integrity-Token');
const requestNonce = req.headers.get('X-Request-Nonce');
const isDebugBuild = req.headers.get('X-Debug-Build') === 'true';

// تجاوز في debug إذا كان مسموحاً
if (ALLOW_DEBUG_BYPASS && isDebugBuild) {
  console.log('Debug build detected, skipping integrity check');
} else {
  // 1. التحقق من وجود الرمز والـ nonce
  if (!integrityToken || !requestNonce) {
    return jsonError(403, 'INTEGRITY_MISSING', 'Integrity token and nonce are required');
  }

  // 2. استدعاء Google Play Integrity API لفك تشفير الرمز
  let integrityPassed = false;
  try {
    integrityPassed = await verifyIntegrityToken(integrityToken, requestNonce);
  } catch (e) {
    integrityPassed = false;
  }

  // 3. التحقق من نتيجة الفك
  if (!integrityPassed) {
    return jsonError(403, 'INTEGRITY_FAILED', 'App integrity check failed, update the app');
  }
}
```

#### دالة `verifyIntegrityToken` (السطور 166-218):

```typescript
async function verifyIntegrityToken(
  integrityToken: string,
  requestNonce: string,
): Promise<boolean> {
  // 1. الحصول على Access Token من Service Account
  const accessToken = await getGoogleAccessToken();

  // 2. استدعاء Google Play Integrity API
  const res = await fetch(
    `https://playintegrity.googleapis.com/v1/${EXPECTED_PACKAGE_NAME}:decodeIntegrityToken`,
    {
      method: 'POST',
      headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ integrityToken }),
    },
  );

  const payload: IntegrityPayload = data.tokenPayloadExternal ?? {};

  // 3. التحقق من تطابق الـ Nonce (حماية من إعادة التشغيل)
  const expectedHash = await sha256Base64(requestNonce);
  if (payload.requestDetails?.requestHash !== expectedHash) return false;

  // 4. التحقق من حداثة الرمز (أقل من 5 دقائق)
  const issued = Number(payload.requestDetails?.timestampMillis ?? 0);
  if (!issued || Date.now() - issued > 5 * 60 * 1000) return false;

  // 5. التحقق من التعرف على التطبيق (PLAY_RECOGNIZED)
  if (payload.appIntegrity?.appRecognitionVerdict !== 'PLAY_RECOGNIZED') return false;
  if (payload.appIntegrity?.packageName !== EXPECTED_PACKAGE_NAME) return false;

  // 6. التحقق من نزاهة الجهاز
  const deviceVerdicts = payload.deviceIntegrity?.deviceRecognitionVerdict ?? [];
  if (!deviceVerdicts.includes('MEETS_DEVICE_INTEGRITY')) return false;

  return true;
}
```

---

### 7. **التحقق من معدل الطلبات (Rate Limiting) - من جانب الخادم**
**ملف**: `supabase/functions/ai-proxy/index.ts` (السطور 227-259, 365-376)

```typescript
const limit = checkRateLimit(user.id);
if (!limit.allowed) {
  return jsonError(429, isMinute ? 'RATE_LIMIT_MINUTE' : 'RATE_LIMIT_MONTH', ...);
}
```

---

### 8. **معالجة الطلب واستدعاء Gemini - من جانب الخادم**
**ملف**: `supabase/functions/ai-proxy/index.ts` (السطور 378-422)

بعد اجتياز جميع التحققات، يتم:
1. تحليل جسم الطلب
2. استدعاء Gemini API
3. إرجاع النتيجة

---

## ملخص ترتيب التحققات (Client → Server)

| الترتيب | الخطوة | الجهة | النتيجة عند الفشل |
|----------|---------|--------|-------------------|
| 1 | مصادقة Supabase | Client | 401 UNAUTHENTICATED |
| 2 | توليد Nonce | Client | - (داخلي) |
| 3 | طلب Integrity Token من Google Play | Client | IntegrityException (INTEGRITY_DISABLED, EMPTY_TOKEN, PlayIntegrityException) |
| 4 | إرسال الطلب مع Headers | Client | - |
| 5 | مصادقة Supabase | Server | 401 UNAUTHENTICATED |
| 6 | **التحقق من Play Integrity** | **Server** | **403 INTEGRITY_MISSING / INTEGRITY_FAILED** |
| 7 | Rate Limiting | Server | 429 RATE_LIMIT_MINUTE/MONTH |
| 8 | استدعاء Gemini | Server | 502 UPSTREAM_ERROR |

---

## أكواد الأخطاء المتعلقة بالنزاهة

| الكود | الوصف | المصدر |
|------|--------|--------|
| `INTEGRITY_DISABLED` | Play Integrity غير مكوّن في هذا البناء | Client (IntegrityService) |
| `EMPTY_TOKEN` | رمز نزاهة فارغ من Google Play | Client (IntegrityService) |
| `INTEGRITY_MISSING` | لم يتم إرسال رمز النزاهة أو الـ nonce | Server (Edge Function) |
| `INTEGRITY_FAILED` | فشل التحقق من الرمز (Nonce mismatch، غير معترف، جهاز غير مستوفٍ، منتهي الصلاحية) | Server (Edge Function) |
| `PlayIntegrityException` | أخطاء من Google Play Services (NETWORK_ERROR، API_NOT_AVAILABLE، إلخ) | Client (flutter_play_integrity_wrapper) |

---

## إعدادات البناء (Build Configuration)

**ملف**: `lib/core/app_config.dart`

```dart
static int? get cloudProjectNumber => const int.fromEnvironment('CLOUD_PROJECT_NUMBER');
static bool get strictIntegrityCheck => const bool.fromEnvironment('STRICT_INTEGRITY_CHECK', defaultValue: true);
static bool get isSupabaseConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
```

- `CLOUD_PROJECT_NUMBER`: رقم مشروع Google Cloud (مطلوب لـ Play Integrity)
- `STRICT_INTEGRITY_CHECK`: `true` للإنتاج، `false` للـ debug builds
- يتم حقنها عبر `--dart-define` عند البناء

---

## المتغيرات البيئية المطلوبة على الخادم (Supabase Secrets)

```bash
supabase secrets set \
  GEMINI_API_KEY="..." \
  GOOGLE_SERVICE_ACCOUNT_JSON="..." \
  EXPECTED_PACKAGE_NAME="com.saadmohammed2000.flex_reminder" \
  ALLOW_DEBUG_BYPASS="false" \
  RATE_LIMIT_PER_MINUTE="10" \
  RATE_LIMIT_PER_MONTH="500"
```

- `GOOGLE_SERVICE_ACCOUNT_JSON`: حساب خدمة له دور `playintegrity` scope
- يجب أن يطابق `EXPECTED_PACKAGE_NAME` اسم الحزمة في Play Console