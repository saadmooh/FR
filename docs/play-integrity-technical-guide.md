# دليل تقني: تكامل Google Play Integrity API مع Flutter وSupabase Edge Functions

> مستند مرجعي قابل لإعادة الاستخدام في أي تطبيق Flutter يحتاج حماية الـ backend من الطلبات المزيّفة أو من تطبيقات معدَّلة (modded/cracked).

---

## 1. لماذا نحتاج Play Integrity أصلاً؟

عندما يكون عندك backend (مثل Supabase Edge Function) يستدعي خدمة مدفوعة أو محدودة الحصة (مثل Gemini API)، فإن مصادقة المستخدم وحدها (Supabase Auth / Firebase Auth) لا تكفي. أي شخص يملك حساب مستخدم صالح يقدر:

- يستخرج التوكن (JWT) من تطبيقك ويستدعي الـ backend مباشرة من Postman أو سكربت خاص به، متجاوزًا واجهة التطبيق كليًا.
- يعدّل نسخة APK من تطبيقك (إزالة إعلانات، رفع حدود الاستخدام، إلخ) وتظل الطلبات "شرعية" من ناحية المصادقة.

**Play Integrity API** يجيب على سؤال مختلف تمامًا عن "من هذا المستخدم؟" — هو يجيب على: **"هل هذا الطلب قادم فعليًا من نسخة أصلية وغير معدَّلة من تطبيقك، مثبّتة عبر Google Play، على جهاز غير مُخترق (rooted/emulated)؟"**

النتيجة: توكن (JWT) موقّع من Google، يرسله العميل مع كل طلب حساس، ويفكّه السيرفر عبر واجهة Google الرسمية.

---

## 2. الفرق الجوهري بين نوعي الـ API — هذا هو مصدر أغلب الأخطاء

هذه النقطة تحديدًا كانت سبب المشكلة الأصلية، ولازم تُفهم جيدًا قبل أي تطبيق جديد:

| | **Classic API (Nonce-based)** | **Standard API (Request Hash)** — الموصى به حاليًا |
|---|---|---|
| الطريقة | `setNonce(nonce)` | `setRequestHash(hash)` |
| يحتاج ربط Google Cloud Project؟ | لا (اختياري لبعض السيناريوهات) | نعم، إلزامي (`cloudProjectNumber`) لأغراض الحصص |
| الحقل داخل التوكن المفكوك | `requestDetails.nonce` | `requestDetails.requestHash` |
| هل Google تعيد hash القيمة المرسلة؟ | لا — تعيد نفس القيمة كـ echo داخل `nonce` | لا أيضًا — تعيد نفس القيمة كـ echo داخل `requestHash` |
| الحالة | قديم، في طريقه للإيقاف التدريجي | الحالي والمستقبلي |

> ⚠️ **الخطأ الشائع:** الاعتقاد بأن Google تطبّق SHA-256 على القيمة قبل إرجاعها. **هذا غير صحيح في كلا النوعين.** القيمة التي ترسلها (nonce أو requestHash) تُعاد كما هي تمامًا داخل التوكن. فإذا قارن السيرفر `sha256(القيمة المُرسلة)` بالقيمة المُعادة، ستفشل المقارنة دائمًا — وهذا بالضبط ما حصل في القضية التي شخّصناها.

> ⚠️ **خطأ شائع ثانٍ:** وجود `cloudProjectNumber` في استدعاء المكتبة لا يعني تلقائيًا أنها تستخدم Standard API. بعض الـ wrappers (مثل `flutter_play_integrity_wrapper`) تقبل `cloudProjectNumber` لأغراض الحصص لكنها داخليًا لا تزال تستدعي `setNonce()` الكلاسيكي. **الطريقة الوحيدة للتأكد هي فحص التوكن الفعلي المُرجَع من الـ diagnostic**: إذا وجدت `requestDetails.nonce` موجودًا و`requestDetails.requestHash` غائبًا (`N/A`)، فأنت تستخدم الـ Classic API فعليًا، بغض النظر عن اسم الباراميتر في كود Dart.

---

## 3. تسلسل العملية الكاملة (End-to-End Flow)

```
┌─────────────┐     1. توليد nonce عشوائي        ┌──────────────┐
│   Flutter    │ ───────────────────────────────▶ │  الجهاز       │
│   Client     │     2. طلب integrity token         │  (Play        │
│              │ ◀─────────────────────────────── │   Services)    │
└──────┬───────┘     3. توكن JWT موقّع من Google    └──────────────┘
       │
       │ 4. إرسال الطلب مع:
       │    - Authorization: Bearer <supabase_jwt>
       │    - X-Integrity-Token: <توكن Google>
       │    - X-Request-Nonce: <نفس الـ nonce الأصلي>
       ▼
┌──────────────────┐
│  Supabase Edge    │  5. التحقق من هوية المستخدم (Supabase Auth)
│  Function         │  6. الحصول على Google OAuth2 access token
│  (ai-proxy)        │     عبر service account (JWT/RS256)
│                    │  7. استدعاء decodeIntegrityToken على توكن العميل
│                    │  8. مطابقة nonce/requestHash + appIntegrity +
│                    │     deviceIntegrity + freshness (< 5 دقائق)
│                    │  9. تطبيق rate limiting
└──────┬─────────────┘
       │ 10. إذا نجحت كل الفحوصات
       ▼
┌──────────────────┐
│  الخدمة المحمية    │  (مثل Gemini API)
│  (Upstream API)   │
└──────────────────┘
```

---

## 4. الكود الأساسي — جانب العميل (Flutter)

### 4.1 توليد nonce عشوائي وربطه بمحتوى الطلب

```dart
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

String generateNonce(String prompt) {
  final random = Random.secure();
  final salt = List<int>.generate(16, (_) => random.nextInt(256));
  // ربط الـ nonce بمحتوى الطلب + ملح عشوائي يمنع إعادة استخدامه (replay)
  final hash = sha256.convert([...utf8.encode(prompt), ...salt]);
  return base64UrlEncode(hash.bytes).replaceAll('=', '');
}
```

**لماذا نربط الـ nonce بمحتوى الطلب (`prompt`)؟** لمنع هجوم "استبدال المحتوى": بدون هذا الربط، يستطيع مهاجم يملك توكن integrity صالح واحد أن يعيد استخدامه مع محتوى مختلف كليًا. ربط الـ nonce بـ hash المحتوى يجعل كل توكن صالحًا لمحتوى واحد فقط.

### 4.2 طلب التوكن من Play Integrity

```dart
import 'package:flutter_play_integrity_wrapper/flutter_play_integrity_wrapper.dart';

final wrapper = FlutterPlayIntegrityWrapper();

final token = await wrapper.requestIntegrityToken(
  cloudProjectNumber: cloudProjectNumber.toString(), // من Google Cloud Console
  nonce: nonce,
);
```

### 4.3 إرسال الطلب مع الهيدرز المطلوبة

```dart
final headers = <String, String>{
  'X-Integrity-Token': token,
  'X-Request-Nonce': nonce, // ⚠️ نفس القيمة الحرفية المُرسلة للتوليد، بدون أي تعديل
};

final response = await client.functions.invoke(
  'ai-proxy',
  headers: headers,
  body: {'prompt': prompt},
);
```

---

## 5. الكود الأساسي — جانب السيرفر (Supabase Edge Function / Deno)

### 5.1 الحصول على Google OAuth2 access token عبر service account

```typescript
async function getGoogleAccessToken(): Promise<string> {
  const sa = JSON.parse(process.env.GOOGLE_SERVICE_ACCOUNT_JSON!);
  const now = Math.floor(Date.now() / 1000);

  const header = base64UrlEncode(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const payload = base64UrlEncode(JSON.stringify({
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/playintegrity',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }));

  const key = await crypto.subtle.importKey(
    'pkcs8', pemToDer(sa.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'],
  );
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5', key, encoder.encode(`${header}.${payload}`),
  );
  const jwt = `${header}.${payload}.${base64UrlEncode(new Uint8Array(signature))}`;

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });
  const data = await res.json();
  return data.access_token;
}
```

### 5.2 فك التوكن والتحقق منه — النسخة الصحيحة (nonce-based)

```typescript
async function verifyIntegrityToken(integrityToken: string, requestNonce: string) {
  const accessToken = await getGoogleAccessToken();

  const res = await fetch(
    `https://playintegrity.googleapis.com/v1/${EXPECTED_PACKAGE_NAME}:decodeIntegrityToken`,
    {
      method: 'POST',
      headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ integrityToken }),
    },
  );
  const data = await res.json();
  const payload = data.tokenPayloadExternal ?? {};

  // ✅ الفحص الصحيح: مقارنة بايتية بعد فك base64، بدون أي hash إضافي
  const nonceMatches = payload.requestDetails?.nonce
    ? bytesEqual(
        base64Decode(payload.requestDetails.nonce),
        base64Decode(requestNonce),
      )
    : false;

  if (!nonceMatches) return { passed: false, reason: 'nonceMismatch' };

  // فحص الحداثة (منع إعادة الاستخدام / replay)
  const issued = Number(payload.requestDetails?.timestampMillis ?? 0);
  if (Date.now() - issued > 5 * 60 * 1000) {
    return { passed: false, reason: 'tokenExpired' };
  }

  // فحص التطبيق
  if (payload.appIntegrity?.appRecognitionVerdict !== 'PLAY_RECOGNIZED') {
    return { passed: false, reason: 'appNotRecognized' };
  }
  if (payload.appIntegrity?.packageName !== EXPECTED_PACKAGE_NAME) {
    return { passed: false, reason: 'packageNameMismatch' };
  }

  // فحص الجهاز
  const deviceVerdicts = payload.deviceIntegrity?.deviceRecognitionVerdict ?? [];
  if (!deviceVerdicts.includes('MEETS_DEVICE_INTEGRITY')) {
    return { passed: false, reason: 'deviceIntegrityFailed' };
  }

  return { passed: true };
}
```

> 💡 **ملاحظة:** إذا اخترت استخدام Standard API بدل Classic (عبر `setRequestHash()` في العميل)، الكود مطابق تمامًا، فقط استبدل `payload.requestDetails?.nonce` بـ `payload.requestDetails?.requestHash`. المنطق (بدون hash إضافي، مقارنة بايتية مباشرة) لا يتغيّر.

---

## 6. أهم الفحوصات الأربعة التي يجب أن يطبّقها أي backend

1. **تطابق الـ nonce/requestHash** — يثبت أن هذا التوكن أُصدر لهذا الطلب بالذات، وليس توكنًا مُعاد استخدامه من طلب سابق (replay attack).
2. **الحداثة (Freshness)** — `timestampMillis` يجب أن يكون خلال آخر 5 دقائق تقريبًا، لمنع تخزين توكن صالح وإعادة استخدامه لاحقًا.
3. **التعرّف على التطبيق (`appRecognitionVerdict === 'PLAY_RECOGNIZED'`)** — يثبت أن APK الموقّع مطابق لما تم رفعه على Google Play، وأن اسم الحزمة (`packageName`) مطابق للمتوقع.
4. **سلامة الجهاز (`deviceRecognitionVerdict`)** — يحتوي على قيم مثل `MEETS_BASIC_INTEGRITY` و`MEETS_DEVICE_INTEGRITY`؛ يمكن أن تطلب أحدهما أو كليهما حسب مستوى الصرامة المطلوب.

---

## 7. قائمة تحقق لإعادة الاستخدام في تطبيق جديد

- [ ] إنشاء Google Cloud Project وربطه بتطبيق Play Console (`cloudProjectNumber`).
- [ ] إنشاء service account بصلاحية `playintegrity` وتنزيل ملف JSON الخاص به.
- [ ] تخزين `GOOGLE_SERVICE_ACCOUNT_JSON` كـ secret على السيرفر — **أبدًا** داخل كود العميل.
- [ ] تحديد صراحة: هل ستستخدم Classic (`setNonce`) أم Standard (`setRequestHash`)؟ وتوثيق القرار في الكود بتعليق واضح.
- [ ] ربط الـ nonce/hash بمحتوى الطلب الفعلي (وليس قيمة عشوائية منفصلة) لمنع استبدال المحتوى.
- [ ] عند التحقق في السيرفر: **مقارنة بايتية مباشرة بعد فك base64، بدون أي hash إضافي من جهة السيرفر.**
- [ ] فحص الحداثة (freshness window) — 5 دقائق نقطة انطلاق معقولة.
- [ ] فحص `appRecognitionVerdict` و`packageName`.
- [ ] فحص `deviceRecognitionVerdict`.
- [ ] إرجاع `diagnostic` مفصّل في حالات الفشل أثناء التطوير فقط (يُفضّل إخفاؤه أو تقليصه في الإنتاج لتفادي تسريب معلومات مفيدة لمهاجم).
- [ ] إضافة rate limiting منفصل عن فحص integrity (integrity يثبت "من أنت"، والـ rate limit يحدد "كم مرة").
- [ ] اختبار الفشل المتعمد (توكن مزيّف، nonce غير مطابق) للتأكد أن السيرفر يرفض بشكل صحيح، وليس فقط اختبار المسار الناجح.

---

## 8. خلاصة الدرس المستفاد من القضية الأصلية

الخطأ لم يكن في تصميم النظام (طبقات الحماية الأربع: Auth → Integrity → Rate Limit → Upstream كانت سليمة معماريًا)، بل في **افتراض خاطئ حول سلوك Google API**: توقّع أن القيمة المُرسلة (nonce) تُعاد مُشفّرة (hashed) من طرف Google، بينما الواقع أنها تُعاد كما هي (echo). هذا النوع من الأخطاء صعب اكتشافه من قراءة الكود وحده لأن كل طبقة تبدو منطقية بمعزل عن الأخرى — الحل الحاسم جاء من قراءة حقل `Failed checks: requestHashMissing` و`Request hash: N/A` في diagnostic فعلي، وليس من التخمين النظري. **الدرس العملي:** دائمًا فعّل diagnostic مفصّل أثناء التطوير، ولا تكتفِ بكود HTTP status عند تشخيص أخطاء integrity.