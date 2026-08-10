# حل مشكلة فشل التحقق من سلامة التطبيق (INTEGRITY_FAILED)

## ملخص المشكلة

عند بناء التطبيق في وضع التطوير (debug) أو تثبيته مباشرة (sideload) على أجهزة أندرويد، كان يظهر الخطأ التالي عند محاولة استخدام ميزة الذكاء الاصطناعي:

```
Error saving post: فشل التحقق من التطبيق (INTEGRITY_FAILED): App integrity check failed, update the app to the latest version
Code: INTEGRITY_FAILED
Status: 403
Retryable: false
```

حتى مع تعيين `STRICT_INTEGRITY_CHECK=false`، كان الخطأ يظهر لأن التطبيق كان لا يزال يرسل رمز سلامة (integrity token) غير صالح إلى دالة Supabase Edge Function، والتي بدورها كانت ترفض الطلب.

---

## السبب الجذري

### 1. آلية عمل Play Integrity
- **Play Integrity API** تتحقق من أن التطبيق موقع وموزع عبر متجر Google Play
- تطبيقات التطوير (debug builds) والتطبيقات المثبتة يدوياً (sideloaded) **لا تمر** بهذا التحقق
- Google ترجع `appRecognitionVerdict` غير مساوي لـ `PLAY_RECOGNIZED`

### 2. سلوك الكود السابق
في `ai_proxy_service.dart`، حتى عند فشل الحصول على رمز السلامة:
```dart
// الكود القديم - يرسل التوكن حتى لو فشل
if (integrityToken != null) {
  headers['X-Integrity-Token'] = integrityToken;
  headers['X-Request-Nonce'] = nonce;
}
```
كان التطبيق يرسل التوكن الفارغ/الفاشل، مما يؤدي لرفض الطلب من السيرفر.

### 3. متطلبات الدالة الطرفية (Edge Function)
الدالة `ai-proxy` في Supabase كانت **تتطلب** وجود الرأسين:
- `X-Integrity-Token`
- `X-Request-Nonce`

وإذا كانا مفقودين، ترجع `INTEGRITY_MISSING` (403).

---

## الحل المطبق

### 1. تعديل جانب العميل (Client-side) - `lib/services/ai_proxy_service.dart`

**أ. عدم إرسال التوكن عند الفشل:**
```dart
bool integrityFailed = false;
try {
  integrityToken = await _integrity.requestIntegrityToken(nonce: nonce);
} on IntegrityException catch (e) {
  integrityFailed = true;
  if (strictIntegrityCheck) {
    throw AiProxyException(...); // يرمي خطأ فقط في الوضع الصارم
  }
}

// إرسال التوكن فقط إذا نجح ولم يفشل
if (integrityToken != null && !integrityFailed) {
  headers['X-Integrity-Token'] = integrityToken;
  headers['X-Request-Nonce'] = nonce;
}
```

**ب. إرسال رأس `X-Debug-Build` للبنيات التجريبية:**
```dart
if (!strictIntegrityCheck && kDebugMode) {
  headers['X-Debug-Build'] = 'true';
}
```

**ج. معالجة خطأ `INTEGRITY_MISSING` بذكاء:**
```dart
case 'INTEGRITY_MISSING':
  if (!strictIntegrityCheck) {
    return AiProxyException(e.status, code, 'Integrity not available in debug build');
  }
  return AiProxyException(...); // خطأ كامل في الوضع الصارم
```

---

### 2. تعديل جانب الخادم (Server-side) - `supabase/functions/ai-proxy/index.ts`

**أ. متغير بيئة جديد للتحكم في التجاوز:**
```typescript
const ALLOW_DEBUG_BYPASS = process.env.ALLOW_DEBUG_BYPASS === 'true';
```

**ب. منطق التجاوز للبنيات التجريبية:**
```typescript
const isDebugBuild = req.headers.get('X-Debug-Build') === 'true';

if (ALLOW_DEBUG_BYPASS && isDebugBuild) {
  console.log('Debug build detected, skipping integrity check');
} else {
  // التحقق العادي من السلامة
  if (!integrityToken || !requestNonce) {
    return jsonError(403, 'INTEGRITY_MISSING', '...');
  }
  // ... التحقق من التوكن
}
```

---

## خطوات النشر والتفعيل

### 1. نشر الدالة المحدثة
```bash
supabase functions deploy ai-proxy
```

### 2. تفعيل وضع التجاوز (مرة واحدة)
```bash
supabase secrets set ALLOW_DEBUG_BYPASS=true
```

### 3. بناء التطبيق مع تعطيل التحقق الصارم
```bash
# للبناء التجريبي
flutter build apk --debug --dart-define=STRICT_INTEGRITY_CHECK=false

# للبناء النهائي (release) مع تعطيل التحقق الصارم
flutter build apk --release --dart-define=STRICT_INTEGRITY_CHECK=false
```

---

## حالات الاستخدام

| البيئة | `STRICT_INTEGRITY_CHECK` | `kDebugMode` | `ALLOW_DEBUG_BYPASS` | السلوك |
|----------|--------------------------|--------------|----------------------|---------|
| تطوير محلي | `false` | `true` | `true` | **يتجاوز التحقق** ✅ |
| اختبار داخلي (TestFlight/Firebase) | `false` | `false` | `true` | يطلب سلامة (قد يفشل) |
| متجر Play (إنتاج) | `true` | `false` | `false` | **تحقق كامل مطلوب** 🔒 |
| إنتاج مع تعطيل مؤقت | `false` | `false` | `true` | يتجاوز التحقق ⚠️ |

---

## ملاحظات أمنية هامة

⚠️ **تحذير**: تفعيل `ALLOW_DEBUG_BYPASS=true` في الإنتاج **يقلل الأمان** لأنه يسمح للتطبيقات غير الموقعة بالوصول للذكاء الاصطناعي.

**أفضل الممارسات:**
1. اترك `ALLOW_DEBUG_BYPASS=true` فقط في بيئات التطوير/الاختبار
2. في الإنتاج، تأكد من:
   - `STRICT_INTEGRITY_CHECK=true`
   - `GCP_CLOUD_PROJECT_NUMBER` مضبوط بشكل صحيح
   - التطبيق موقع وموزع عبر Google Play Console
3. راقب سجلات Supabase للكشف عن محاولات تجاوز مشبوهة

---

## التحقق من الحل

بعد النشر، اختبر بالخطوات التالية:

1. **بناء تجريبي:**
   ```bash
   flutter build apk --debug --dart-define=STRICT_INTEGRITY_CHECK=false
   ```
   تثبيت APK → فتح التطبيق → تجربة ميزة الذكاء الاصطناعي → **يجب أن تعمل**

2. **مراجعة سجلات Supabase:**
   - اذهب إلى Dashboard → Edge Functions → ai-proxy → Logs
   - يجب أن ترى: `Debug build detected, skipping integrity check`

3. **بناء إنتاج (للتأكد من عدم كسر الإنتاج):**
   ```bash
   flutter build apk --release --dart-define=STRICT_INTEGRITY_CHECK=true
   ```
   اختبار على جهاز مع التطبيق من متجر Play → **يجب أن تعمل مع التحقق الكامل**

---

## الملفات المعدلة

| الملف | نوع التغيير |
|--------|-------------|
| `lib/services/ai_proxy_service.dart` | منطق العميل: تجاهل التوكن الفاشل، إرسال رأس debug |
| `supabase/functions/ai-proxy/index.ts` | منطق الخادم: تجاوز التحقق للبنيات التجريبية |

---

## الخلاصة

الحل يفصل بين **بيئة التطوير** (حيث التحقق مستحيل) و**بيئة الإنتاج** (حيث التحقق إلزامي)، مع الحفاظ على الأمان عبر:
- متغير بيئة خادم (`ALLOW_DEBUG_BYPASS`) للتحكم المركزي
- فحص `kDebugMode` على العميل لضمان عدم استغلال التجاوز في البناء النهائي
- معالجة ذكية للأخطاء لتجنب إرباك المستخدم