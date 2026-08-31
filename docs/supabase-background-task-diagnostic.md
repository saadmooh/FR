# تشخيص توقف عملية Supabase عند إغلاق التطبيق (Flutter - Android)

تاريخ التحليل: 2026-08-27

---

## 1. آلية التنفيذ في الخلفية (Background Execution Mechanism)

**النتيجة:** ✅ يستخدم `workmanager` package بشكل صحيح

- `Workmanager().initialize(callbackDispatcher)` في `main.dart:214`
- `registerOneOffTask` في `notification_service.dart:570` و `workmanager_service.dart:421`
- المهام **one-off** (ليست periodic)، مجدولة بـ `initialDelay` يعتمد على وقت التذكير + دقيقة واحدة
- **لا توجد مشكلة المهام الدورية < 15 دقيقة** - يستخدم مهام لمرة واحدة بتأخيرات ديناميكية

---

## 2. استدعاء Callback Dispatcher

**النتيجة:** ✅ `@pragma('vm:entry-point')` موجود بشكل صحيح

- على `callbackDispatcher()` في `workmanager_service.dart:518-521`
- أيضاً على `_workmanagerCallback()` في السطر 201
- **كلاهما موثق بشكل صحيح** - لن يتم حذفهما أثناء tree shaking في release mode

---

## 3. تهيئة Supabase داخل الـ Isolate المنفصل ❌ **مشكلة حرجة**

**الحالة الحالية:**
- Supabase يتم تهيئته داخل `_initBackgroundServices()` الذي يُستدعى من داخل الـ callback ✅
- الأسطر 27-73 في `workmanager_service.dart`
- يستدعي `Supabase.initialize()` مع URL و anon key
- يعيد استعادة الجلسة من Firebase user إذا لزم الأمر (الأسطر 53-70)

**المشكلة:**
- `AppConfig.isSupabaseConfigured` قد تكون `false` في بيئة الخلفية إذا لم تمرر `--dart-define` القيم عند البناء
- يجب التحقق من أن البناء للـ release يتضمن هذه المتغيرات

---

## 4. الصلاحيات ونظام توفير الطاقة

| الصلاحية | الحالة |
|-----------|--------|
| `RECEIVE_BOOT_COMPLETED` | ✅ في `AndroidManifest.xml:3` |
| `FOREGROUND_SERVICE` | ❌ **مفقود** - مطلوب للعمل في الخلفية على Android 14+ |
| `SCHEDULE_EXACT_ALARM` | ✅ في Manifest |
| `USE_EXACT_ALARM` | ✅ في Manifest |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | ✅ في Manifest + مطلوبة Runtime في `notification_service.dart:127` |

**مشكلة حرجة:** لا يوجد `FOREGROUND_SERVICE` permission في Manifest. مطلوب لـ WorkManager للعمل بشكل موثوق على Android 14+.

---

## 5. معالجة الأخطاء والـ Logging

**Try/Catch موجود** ✅ في `workmanager_service.dart:235-514` - يغلف العملية بأكملها

**تسجيل محلي للأخطاء** ✅ في `SharedPreferences` عند الفشل:
- السطر 470: `prefs.setString('last_ai_reschedule_error', e.toString())`
- يعرض أيضاً Notification محلياً عند الفشل (الأسطر 473-512)

---

## 6. الاتصال بالشبكة عند التنفيذ

**لا يوجد تحقق من الاتصال بالشبكة** ❌
- لا يستخدم `connectivity_plus` قبل استدعاء Supabase
- `AiProxyService.sendPrompt()` لديه **retry logic** داخلي لأخطاء الشبكة (الأسطر 193-208 في `ai_proxy_service.dart`):
  - يعيد المحاولة مرة واحدة لـ `SocketException`, `http.ClientException`, `TimeoutException`
  - لكن لا يتحقق مسبقاً من توفر الإنترنت

---

## الخلاصة: الأسباب المحتملة للتوقف الصامت

1. **FOREGROUND_SERVICE permission مفقود** في AndroidManifest.xml - حاسم لـ Android 14+
2. **بناء Release بدون `--dart-define`** لقيم Supabase → `AppConfig.isSupabaseConfigured = false` → يتخطى التهيئة
3. **Firebase Auth غير متاح** في الخلفية → فشل استعادة جلسة Supabase (السطر 56-66 في workmanager_service.dart)
4. **لا يوجد تحقق مسبق من الشبكة** - يفشل بصمت إذا لا يوجد إنترنت

---

## إصلاحات مقترحة (بالأولوية)

### 1. أضف لـ AndroidManifest.xml:
```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
```

### 2. تأكد من بناء Release مع:
```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=... \
  --dart-define=GCP_CLOUD_PROJECT_NUMBER=...
```

### 3. أضف تحقق شبكة في `_workmanagerCallback` قبل استدعاء AI:
```dart
import 'package:connectivity_plus/connectivity_plus.dart';

final connectivity = await Connectivity().checkConnectivity();
if (connectivity == ConnectivityResult.none) {
  debugPrint('No internet, skipping');
  return true; // سيعيد المحاولة لاحقاً
}
```

### 4. أضف logging أوفر في `_initBackgroundServices` لتأكيد نجاح التهيئة.

---

## ملفات ذات صلة

- `lib/services/workmanager_service.dart` - منطق الخلفية الرئيسي
- `lib/main.dart` - تهيئة WorkManager و Supabase
- `lib/services/notification_service.dart` - جدولة مهام WorkManager
- `lib/services/ai_proxy_service.dart` - استدعاءات AI مع retry logic
- `android/app/src/main/AndroidManifest.xml` - الصلاحيات