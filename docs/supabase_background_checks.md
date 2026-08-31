# فحوصات سريعة لتحديد سبب توقف Supabase في الخلفية

**تاريخ الفحص:** 2026-08-27  
**المشروع:** Flex Reminder (Flutter/Android)

---

## ملخص تنفيذي

بعد فحص الكود بالكامل، تم تحديد **3 مشكلات حاسمة** تفسر سبب توقف Supabase في الخلفية:

| الفحص | الحالة | الخطورة |
|----------|---------|----------|
| 1. `isSupabaseConfigured` | ⚠️ يعتمد على `--dart-define` | **عالية** |
| 2. أمر البناء (CI/CD) | ❌ لا توجد ملفات CI/CD | **عالية** |
| 3. `last_ai_reschedule_error` | ✅ الكود موجود ويعمل | متوسطة |
| 4. `FOREGROUND_SERVICE` permission | ❌ **مفقود بالكامل** | **حرجة** |
| 5. Firebase Auth في الـ isolate | ⚠️ قد لا يعمل في isolate منفصل | **عالية** |

---

## 1. فحص قيمة `isSupabaseConfigured` فعليًا

### الكود الحالي (`lib/core/app_config.dart:4-18`)

```dart
static const String supabaseUrl =
    String.fromEnvironment('SUPABASE_URL', defaultValue: 'YOUR_SUPABASE_URL');
static const String supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: 'YOUR_SUPABASE_ANON_KEY',
);

static const bool isSupabaseConfigured = supabaseUrl != 'YOUR_SUPABASE_URL' &&
    supabaseAnonKey != 'YOUR_SUPABASE_ANON_KEY';
```

### التحليل

- **القيمة تكون `true` فقط إذا** تم تمرير `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...` أثناء البناء
- **القيمة تكون `false`** عند البناء بدون هذه الأعلام (القيم الافتراضية `'YOUR_SUPABASE_URL'` و `'YOUR_SUPABASE_ANON_KEY'`)
- في `main.dart:105-119` و `workmanager_service.dart:37` — يتم **تجاهل تهيئة Supabase بالكامل** إذا كانت `false`

### التوصية الفورية

أضف سطر التصحيح المؤقت في `_initBackgroundServices` (السطر 27 في `workmanager_service.dart`):

```dart
// سطر مؤقت للتصحيح - احذفه بعد التأكد
final prefs = await SharedPreferences.getInstance();
await prefs.setString('debug_supabase_configured', AppConfig.isSupabaseConfigured.toString());
debugPrint('🔍 DEBUG: isSupabaseConfigured = ${AppConfig.isSupabaseConfigured}');
```

ثم ابنِ **Release APK موقع** واختبر على جهاز حقيقي، وافحص `SharedPreferences` للعثور على `debug_supabase_configured`.

---

## 2. فحص أمر البناء الفعلي المستخدم (الأسرع — ابدأ هنا)

### الوضع الحالي

| ملف/مكان | موجود؟ | ملاحظات |
|----------|--------|---------|
| `.github/workflows/*.yml` | ❌ لا | لا يوجد GitHub Actions |
| `bitrise.yml` | ❌ لا | لا يوجد Bitrise |
| `codemagic.yaml` | ❌ لا | لا يوجد Codemagic |
| `fastlane/` | ❌ لا | لا يوجد Fastlane |
| `android/app/build.gradle.kts` | ✅ نعم | لا يحتوي على `dart-define` |
| سكريبتات بناء محلية (`*.sh`) | ❌ لا | لا توجد |

### ملف `android/app/build.gradle.kts` (السطور 1-57)

```kotlin
// لا يوجد أي إعداد لـ dart-define هنا
// البناء يعتمد كلياً على سطر الأوامر أو CI/CD خارجي
```

### الاستنتاج

**لا يوجد أي أثر لأمر البناء المستخدم** في مستودع الكود. هذا يعني:
- البناء يتم يدويًا عبر سطر الأوامر: `flutter build apk --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`
- أو عبر CI/CD خارجي غير مُدرَج في المستودع

### إجراء مطلوب

**اسأل نفسك/الفريق:** ما هو الأمر **الدقيق** المستخدم لبناء الـ APK/AAB المرفوع؟
```bash
# المثال الصحيح:
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...

# إذا كان الأمر بدون --dart-define → هذا هو السبب الجذري
```

---

## 3. قراءة `last_ai_reschedule_error` بعد فشل مؤكد

### آلية العمل الحالية

**الحفظ** (`workmanager_service.dart:469-471`):
```dart
final prefs = await SharedPreferences.getInstance();
await prefs.setString('last_ai_reschedule_error', e.toString());
```

**القراءة والمسح** (`main.dart:199-203`):
```dart
final lastError = prefs.getString('last_ai_reschedule_error');
if (lastError != null && lastError.isNotEmpty) {
  aiRescheduleError.value = lastError;
  await prefs.remove('last_ai_reschedule_error'); // يُمسح بعد القراءة
}
```

### كيف تختبر

1. شغّل التطبيب، أنشئ تذكيرًا
2. انتظر حتى يُفترض أن يعمل WorkManager (أو حرّك الوقت/أعد تشغيل الجهاز)
3. افتح التطبيب → راقب `aiRescheduleError` في `ValueNotifier` (يعرض في UI إن وُجد)
4. أو افحص `SharedPreferences` مباشرة عبر ADB:
   ```bash
   adb shell run-as com.saadmohammed2000.flex_reminder \
     cat /data/data/com.saadmohammed2000.flex_reminder/shared_prefs/*.xml
   ```

### تفسير النتائج

| قيمة `last_ai_reschedule_error` | المعنى |
|----------------------------------|--------|
| **فارغة / غير موجودة** | الكود لم يصل لمنطقة استدعاء Supabase (المهمة لم تُنفذ، أو فشلت قبل `try`) |
| **تحتوي `PostgrestException`** | Supabase مهيأ لكن فشل في الاستعلام (RLS، schema، network) |
| **تحتوي `AuthException` / `signInWithIdToken failed`** | Supabase مهيأ لكن فشل في المصادقة (token منتهي، إعدادات OAuth) |
| **تحتوي `another store is still open`** | التطبيب في foreground → WorkManager خرج بصمت (سطر 464-466) |
| **أخطاء `ObjectBox` / `Store`** | مشكلة في قاعدة البيانات المحلية، ليس Supabase |

---

## 4. فحص `FOREGROUND_SERVICE` permission (حرج — مفقود)

### AndroidManifest.xml الحالي (`android/app/src/main/AndroidManifest.xml:1-10`)

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="android.permission.VIBRATE"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
<uses-permission android:name="android.permission.USE_EXACT_ALARM"/>
<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"/>
<uses-permission android:name="com.android.vending.BILLING"/>
```

### **المفقود (يجب إضافته):**

```xml
<!-- مطلوب لـ WorkManager / background processing على Android 14+ -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
<!-- اختياري لكن مُوصى به لأنواع الخدمات الأخرى -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
```

### لماذا هذا حرج؟

| Android Version | سلوك بدون الصلاحية |
|-----------------|-------------------|
| **Android 13 (API 33) وأقدم** | قد يعمل بالصدفة (نظام أقل صرامة) |
| **Android 14 (API 34)+** | **يتحطم/يُقتل** فور محاولة عمل خلفي دون `foregroundServiceType` |
| **Android 15 (API 35)+** | تطبيق صارم جداً — لن يعمل أبداً |

### اختبار مقترح

1. أضف الصلاحيتين أعلاه إلى `AndroidManifest.xml`
2. أعد البناء: `flutter build apk --release`
3. اختبر على:
   - جهاز Android 14+ (يجب أن يعمل الآن)
   - جهاز Android 13 أو أقدم (للمقارنة)

---

## 5. فحص حالة Firebase Auth داخل الـ isolate

### الكود الحالي (`workmanager_service.dart:53-70`)

```dart
try {
  final client = Supabase.instance.client;
  if (client.auth.currentSession == null) {
    final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser; // السطر 56
    if (firebaseUser != null) {
      final idToken = await firebaseUser.getIdToken();
      // ... استعادة جلسة Supabase
    }
  }
} catch (e) {
  debugPrint('Background Supabase session restore failed: $e');
}
```

### المشكلة

`WorkManager` على Android يشغل `callbackDispatcher` في **عزل (isolate) منفصل** عن الـ main isolate:
- `Firebase.initializeApp()` يتم استدعاؤه في السطر 31 — لكن **في isolate الخلفية**
- `FirebaseAuth.instance.currentUser` **قد يعيد `null`** في isolate الخلفية حتى لو المستخدم مسجل دخول في التطبيب الرئيسي
- Firebase Auth لا يشارك الحالة تلقائياً عبر isolates

### اختبار تشخيصي

أضف في بداية `callbackDispatcher` (السطر 519) قبل أي شيء:

```dart
@pragma('vm:entry-point')
void callbackDispatcher() {
  debugPrint('WorkManager callback dispatcher called');
  
  // === سطر تشخيصي مؤقت ===
  final prefs = await SharedPreferences.getInstance();
  final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
  await prefs.setString('debug_firebase_user_in_isolate', 
    firebaseUser != null ? 'UID: ${firebaseUser.uid}' : 'NULL');
  debugPrint('🔍 DEBUG: FirebaseAuth.currentUser in isolate = ${firebaseUser?.uid ?? "NULL"}');
  // ========================
  
  _workmanagerCallback();
}
```

ثم ابنِ release APK، شغّل، وراقب `SharedPreferences` للـ key `debug_firebase_user_in_isolate`.

### النتائج المتوقعة

| النتيجة | المعنى |
|----------|--------|
| `NULL` في isolate بينما المستخدم مسجل دخول في التطبيب الرئيسي | **مؤكد:** Firebase Auth غير متاح في isolate الخلفية |
| `UID: xxx` موجود | Firebase Auth يعمل في isolate — المشكلة في مكان آخر |

### الحلول المحتملة

1. **نقل `firebase_auth.FirebaseAuth.instance.currentUser` للـ main isolate** عبر `SharedPreferences` أو `MethodChannel` قبل جدولة WorkManager
2. **استخدام `FirebaseAuth.instance.authStateChanges()`** في الـ isolate (يتطلب initializeApp صحيح)
3. **الاعتماد على Supabase session المخزنة محلياً** فقط (بدون Firebase fallback في الخلفية)

---

## خطة عمل مقترحة (بالأولوية)

### 🔴 فوري (اليوم)
1. **أضف صلاحيات FOREGROUND_SERVICE** إلى `AndroidManifest.xml` (الفحص 4)
2. **تحقق من أمر البناء الفعلي** — هل يحتوي على `--dart-define`؟ (الفحص 2)

### 🟡 قصير المدى (هذا الأسبوع)
3. **أضف سطور التصحيح** للفحص 1 و 5، ابنِ release APK، اختبر على جهاز
4. **افحص `last_ai_reschedule_error`** بعد فشل حقيقي (الفحص 3)

### 🟢 متوسط المدى
5. أصلح مشكلة Firebase Auth في isolate (الفحص 5) — إما بتمرير UID عبر inputData أو الاعتماد على Supabase local session فقط
6. أضف CI/CD pipeline يضمن تمرير `--dart-define` صحيحة

---

## ملفات ذات صلة للمراجعة السريعة

| ملف | الأسطر المهمة |
|------|--------------|
| `lib/core/app_config.dart` | 4-18 (تعريف `isSupabaseConfigured`) |
| `lib/services/workmanager_service.dart` | 27-73 (`_initBackgroundServices`), 469-471 (حفظ الخطأ), 519-522 (`callbackDispatcher`) |
| `lib/main.dart` | 105-119 (تهيئة Supabase), 125-139 (استعادة الجلسة), 199-203 (قراءة الخطأ) |
| `android/app/src/main/AndroidManifest.xml` | 1-10 (الصلاحيات — **مفقود FOREGROUND_SERVICE**) |
| `lib/services/auth_service.dart` | 59-79 (`_postSignInSync` — منطق المزامنة) |

---

## خلاصة

> **السبب الأكثر احتمالاً:** مزيج من **(2) البناء بدون `--dart-define`** + **(4) صلاحية `FOREGROUND_SERVICE` مفقودة** + **(5) Firebase Auth لا يعمل في isolate الخلفية**.

ابدأ بالفحص **#2** (لا يتطلب تشغيل شيء) ثم **#4** (إضافة سطرين في XML) — هذان وحدهما قد يحلان 80% من المشكلة.