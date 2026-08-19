# تحليل مشكلة Play Integrity والحلول المقترحة

**التاريخ:** 12 أغسطس 2026  
**الحالة:** تم تحديد السبب الجذري وتطبيق الحل في الكود

---

## 1. ملخص المشكلة

**المشكلة:** رغم تفعيل `STRICT_INTEGRITY_CHECK=true` في `--dart-define`، يستطيع المستخدمون إرسال طلبات ذكاء اصطناعي من تطبيق موقع محلياً (APK مبني محلياً وموقع بمفتاح `upload-keystore.jks`). كان من المتوقع أن يمنع Play Integrity هذه الطلبات.

**الأثر:** التطبيق المحلي غير المنشور على Google Play Store يمكنه تجاوز فحص سلامة التطبيق والوصول إلى API الذكاء الاصطناعي عبر Supabase Edge Function.

---

## 2. تحليل السبب الجذري

### 2.1 كيف يعمل Play Integrity في المشروع

```
تدفق فحص Play Integrity
======================================================================

1. العميل (Flutter)
   - يولد nonce من الـ prompt
   - يطلب integrity token من Google Play Services
   - يرسل الـ token + nonce في headers:
     - X-Integrity-Token
     - X-Request-Nonce

2. الخادم (Supabase Edge Function - ai-proxy)
   - يستقبل الطلب مع headers
   - يتحقق من Supabase Auth (جلسة المستخدم)
   - يفك تشفير الـ integrity token عبر Google Play Integrity API
   - يتحقق من:
     - تطابق nonce (منع إعادة التشغيل - replay attack)
     - حداثة الـ token (أقل من 5 دقائق)
     - PLAY_RECOGNIZED (التطبيق معترف به من Google Play)
     - تطابق package name
     - **MEETS_DEVICE_INTEGRITY** <- **هنا تكمن المشكلة**
   - إذا نجح كل شيء -> يستدعي Gemini API
```

### 2.2 نقطة الفشل المحددة

**الملف:** `supabase/functions/ai-proxy/index.ts`  
**السطر:** 435 (في الدالة `verifyIntegrityToken`)

```typescript
// الكود الأصلي (المشكلة):
if (!deviceVerdicts.includes('MEETS_DEVICE_INTEGRITY')) {
  diagnostic.failedChecks!.push('deviceIntegrityFailed');
  return { passed: false, diagnostic };
}
```

### 2.3 لماذا يمر الـ APK المحلي؟

| معيار الفحص | قيمة متوقعة | قيمة فعلية للـ APK المحلي الموقع بـ upload key |
|--------------|-------------|-------------------------------------------------|
| PLAY_RECOGNIZED | مطلوب | ينجح - المفتاح مسجل في Play Console |
| packageName | مطلوب | ينجح - نفس الـ package name |
| nonce match | مطلوب | ينجح - تم إنشاؤه بشكل صحيح |
| token freshness | < 5 دقائق | ينجح |
| **MEETS_DEVICE_INTEGRITY** | مطلوب (سقف العتاد) | **ينجح - هذا مستوى عتاد، لا مصدر تثبيت** |
| `appLicensingVerdict` | `LICENSED` | **يفشل - `UNLICENSED`/`UNEVALUATED` لأنه لم يُحصّل عبر حساب Play** |

**التفسير التقني (مُصحّح):**
- `deviceRecognitionVerdict` (`MEETS_BASIC`/`MEETS_DEVICE`/`MEETS_STRONG`): يتعلق **بقدرات عتاد الأمان** للجهاز (hardware-backed attestation)، **لا** بمصدر التثبيت. جهاز حقيقي من المتجر قد لا يصل لـ `STRONG` لأسباب عتادية.
- `accountDetails.appLicensingVerdict`: هذه هي الإشارة الحقيقية لـ"مثبّت/محصّل عبر حساب Play مرخّص" (حتى لو مجاني). الـ APK المحلي الموقّع بنفس المفتاح يُرجع `UNLICENSED`/`UNEVALUATED` هنا رغم اجتيازه `PLAY_RECOGNIZED` و`packageName`.

بما أن الـ APK المبني محلياً وموقع بـ `upload-keystore.jks` يعمل على جهاز سليم، فهو يجتاز فحص `MEETS_DEVICE_INTEGRITY` — لكنه **يفشل عند فحص الترخيص** (`licensingNotVerified`/`licensingUnevaluated`)، وهذا هو الفلتر الصحيح.

---

## 3. الحلول المقترحة

### الحل الأول: سقف العتاد `MEETS_DEVICE_INTEGRITY` + فحص الترخيص الإلزامي (مُطبق ✅)

**التغيير:** تعديل `verifyIntegrityToken` في `supabase/functions/ai-proxy/index.ts`

```diff
// فحص العتاد (يبقى عند DEVICE، وليس STRONG):
- if (!deviceVerdicts.includes('MEETS_STRONG_INTEGRITY')) {

// بعد (سقف معقول لسلامة الجهاز فقط):
+ if (!deviceVerdicts.includes('MEETS_DEVICE_INTEGRITY')) {

// + فحص الترخيص الحقيقي (الإشارة لـ"مثبّت من Play"):
+ const licensingVerdict = payload.accountDetails?.appLicensingVerdict;
+ if (licensingVerdict === 'UNEVALUATED') {
+   diagnostic.failedChecks!.push('licensingUnevaluated');
+   return { passed: false, diagnostic };
+ }
+ if (licensingVerdict !== 'LICENSED') {
+   diagnostic.failedChecks!.push('licensingNotVerified');
+   return { passed: false, diagnostic };
+ }
```

**التأثير:**
- يمنع الأجهزة المعطوبة/المكررة (rooted, unlocked bootloader) عبر `MEETS_DEVICE_INTEGRITY`.
- لا يحجب مستخدمين حقيقيين على أجهزة لا تدعم `STRONG` لأسباب عتادية.
- الـ APK المحلي الموقّع بنفس المفتاح يفشل عبر `licensingNotVerified`/`licensingUnevaluated` (لم يُحصّل عبر حساب Play مرخّص) — وهو الفلتر الصحيح لتمييز "ليس من Play".
- يوفر حماية قوية دون حظر أجهزة سليمة شرعية.

**حالة التطبيق:** تم التطبيق في الكود

---

### الحل الثاني: تعطيل allowDebugBypass في قاعدة البيانات

**السبب:** الكود الخلفي يقرأ إعداد `allowDebugBypass` من جدول `ai_proxy_config`. إذا كان `true`، تتجاوز builds التطوير (debug builds) فحص Play Integrity عند إرسال header `X-Debug-Build: true`.

**الأمر لتنفيذه في Supabase SQL Editor:**

```sql
-- تعطيل تجاوز builds التطوير
UPDATE ai_proxy_config 
SET allow_debug_bypass = false 
WHERE id = 1;

-- التحقق من التغيير
SELECT * FROM ai_proxy_config WHERE id = 1;
```

**التأثير:**
- يمنع تجاوز الفحص من builds التطوير
- يعمل فوراً دون إعادة نشر Edge Function

**حالة التطبيق:** مُوصى به للتنفيذ فوراً

---

### الحل الثالث: الجمع بين الحل الأول والثاني (مُوصى به للإنتاج)

تطبيق **كلا** الحلين معاً يوفر حماية متعددة الطبقات:

1. على مستوى Edge Function: سقف العتاد `MEETS_DEVICE_INTEGRITY` + فحص الترخيص `LICENSED` (تم في الكود)
2. على مستوى إعدادات قاعدة البيانات: تعطيل allowDebugBypass (يتطلب تنفيذ SQL)

هذا يضمن أنه حتى إذا تم تجاوز أحد الطبقتين، الطبقة الأخرى تمنع الوصول.

---

### الحل الرابع: إضافة تحقق من شهادة التوقيع (Certificate SHA-256)

**وصف:** التحقق من أن بصمة الشهادة (certificate SHA-256) في الـ integrity token تطابق بصمة الشهادة المعروفة لتطبيقك الرسمي على Play Store.

**التنفيذ المقترح في verifyIntegrityToken:**

```typescript
// إضافة بعد فحص packageName (حوالي السطر 430)
const expectedCertSha256 = 'AA:BB:CC:DD:EE:FF:...'; // بصمة شهادة Play Store الرسمية
const certDigests = payload.appIntegrity?.certificateSha256Digest ?? [];

if (!certDigests.includes(expectedCertSha256)) {
  diagnostic.failedChecks!.push('certificateMismatch');
  return { passed: false, diagnostic };
}
```

**كيفية الحصول على البصمة:**
```bash
# من keystore المستخدم في Play Console
keytool -list -v -keystore upload-keystore.jks -alias upload
# ابحث عن "SHA256:" في المخرجات
```

**ملاحظة:** هذا الحل إضافي للحل الأول، وليس بديلاً عنه.

---

## 4. حالة التنفيذ الحالية

| الحل | الحالة | ملاحظات |
|------|--------|---------|
| طلب MEETS_STRONG_INTEGRITY | مُطبق | تم تعديل supabase/functions/ai-proxy/index.ts السطر 435 |
| تعطيل allowDebugBypass في DB | مُطبق جزئياً | كود الحماية جاهز؛ يتطلب تنفيذ SQL يدوي (غير متاح في هذه البيئة) |
| التحقق من شهادة التوقيع | مُطبق | تمت إضافة EXPECTED_CERT_SHA256 في الكود (السطر 24-26، 435-438) |

---

## 5. خطوات التحقق بعد النشر

### 5.1 اختبار الـ APK المحلي (يجب أن يفشل)

```bash
# بناء APK محلي
flutter build apk --release \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=... \
  --dart-define=GCP_CLOUD_PROJECT_NUMBER=... \
  --dart-define=STRICT_INTEGRITY_CHECK=true

# تثبيت على جهاز فعلي
adb install build/app/outputs/flutter-apk/app-release.apk

# محاولة حفظ منشور (يجب أن يفشل بخطأ INTEGRITY_FAILED)
```

**النتيجة المتوقعة:** رسالة خطأ تحتوي على:
```
[Google Play Integrity] App integrity check failed, update the app to the latest version
(code: INTEGRITY_FAILED, Status: 403)
```

### 5.2 اختبار نسخة Play Store (يجب أن تنجح)

1. نشر نسخة على Play Store (internal testing كحد أدنى)
2. تثبيت من Play Store
3. محاولة حفظ منشور
4. النتيجة المتوقعة: ينجح الحفظ والجدولة

### 5.3 مراقبة السجلات (Logs)

في Supabase Dashboard -> Edge Functions -> ai-proxy -> Logs، ابحث عن:
- stage: "backend_verification"
- failedChecks يحتوي على deviceIntegrityFailed للـ builds المحلية
- passed: true للتثبيتات من Play Store

---

## 6. استكشاف الأخطاء الشائعة

| المشكلة | السبب | الحل |
|----------|-------|-------|
| فشل بـ `licensingUnevaluated` على Play Store | حساب Google غير مسجّل كـ tester في Play Console (شائع في internal/closed testing) | سجّل حسابك كمختبِر في Play Console وحمّل عبر رابط المتجر، لا عبر APK مُثبّت جانبياً |
| فشل بـ `licensingNotVerified` | التطبيق غير محصّل عبر حساب Play مرخّص (APK محلي/sideload) | ثبّت النسخة الرسمية من المتجر |
| خطأ EMPTY_TOKEN أو INTEGRITY_DISABLED | cloudProjectNumber غير مضبوط أو Play Services غير محدث | تحقق من --dart-define=GCP_CLOUD_PROJECT_NUMBER وتحديث Google Play Services على الجهاز |
| nonceMismatch | nonce المرسل لا يطابق ما في الـ token | تأكد من إرسال X-Request-Nonce مطابق للـ nonce المستخدم في توليد الـ token |
| tokenExpired | عمر الـ token تجاوز 5 دقائق | الـ token يجب استخدامه فوراً؛ لا تخزنه لإعادة الاستخدام |

---

## 7. المراجع التقنية

- Play Integrity API - Device Integrity Verdicts
- MEETS_STRONG_INTEGRITY vs MEETS_DEVICE_INTEGRITY
- Supabase Edge Functions - Play Integrity Integration
- Flutter Play Integrity Wrapper

---

## 8. ملخص للمطورين المستقبليين

> **تصحيح مهم (تحديث لاحق):** الفهم السابق لـ `MEETS_STRONG_INTEGRITY` كان **غير دقيق**.
> مستويات `deviceRecognitionVerdict` (`MEETS_BASIC_INTEGRITY` → `MEETS_DEVICE_INTEGRITY` → `MEETS_STRONG_INTEGRITY`) **لا** تتعلق بمصدر التثبيت (Play Store مقابل sideload)، بل بـ**قدرات العتاد الأمنية** للجهاز (hardware-backed attestation مثل StrongBox/keymaster). جهاز حقيقي اشتُري من المتجر قد لا يدعم `STRONG` لأسباب عتادية، بغض النظر عن شرعية التثبيت. المطالبة بـ `STRONG` تحجب مستخدمين حقيقيين على أجهزة أقدم/أقل تجهيزاً.

> **القاعدة الصحيحة:** سقف سلامة الجهاز = `MEETS_DEVICE_INTEGRITY` (يكفي لمنع الأجهزة المعطوبة/المعدّلة). الإشارة الحقيقية لـ"مثبّت من Play فعلاً" هي `accountDetails.appLicensingVerdict == 'LICENSED'`، وليست مستوى عتاد الجهاز.

**ما تم تطبيقه فعلياً في الكود (`verifyIntegrityToken`):**
1. سقف سلامة الجهاز بقي `MEETS_DEVICE_INTEGRITY` (وليس `STRONG`).
2. أُضيف شرط إلزامي على الترخيص: `appLicensingVerdict` يجب أن يكون `LICENSED`، وإلا يفشل الطلب بـ `licensingNotVerified` (أو `licensingUnevaluated` إذا كان `UNEVALUATED` — وهو شائع لحسابات المختبِرين غير المسجّلة في Play Console ولا يعني بالضرورة تحايلاً).

بهذا، الـ APK المبني محلياً والموقّع بنفس المفتاح سيفشل عبر `licensingNotVerified`/`licensingUnevaluated` (لأنه لم يُحصّل عبر حساب Play مرخّص)، بينما تثبيت Play الشرعي يجتاز حتى على جهاز لا يدعم `STRONG`.
