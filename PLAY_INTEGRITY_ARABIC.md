# حل خطأ "app integrity failed" في Google Play Integrity

## فهم المشكلة

خطأ `status 403` مع رسالة **"app integrity failed update the app to the latest version"** يحدث لأن:

1. **التطبيق مثبت من ملف APK محلي** (ليس من متجر Google Play)
2. **Google Play Integrity API** يتحقق من أن التطبيق:
   - موقع بشهادة Play App Signing الرسمية
   - تم تثبيته من متجر Play Store
   - لم يتم تعديله أو إعادة تعبئته

## الحلول

### الحل السريع: تعطيل الفحص الصارم (للتطوير فقط)

```bash
flutter build apk --release --no-tree-shake-icons \
  --dart-define=SUPABASE_URL=https://xwgckczyihcgydcrfzel.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY \
  --dart-define=GCP_CLOUD_PROJECT_NUMBER=1038373651011 \
  --dart-define=STRICT_INTEGRITY_CHECK=false
```

**ملاحظة**: هذا يسمح للتطبيق بالعمل بدون token النزاهة. استخدمه فقط في بيئة التطوير.

---

### الحل الصحيح: تفعيل وضع الاختبار (Play Console)

#### 1. في Google Play Console:
1. اذهب إلى **Release → App integrity**
2. اضغط على **Test responses**
3. أضف **أجهزة الاختبار** (بريد إلكتروني أو device ID)
4. اختر الاستجابات المراد اختبارها:
   - `MEETS_DEVICE_INTEGRITY`
   - `PLAY_RECOGNIZED`
   - `LICENSED`

#### 2. الحصول على Device ID:
```bash
adb shell settings get secure android_id
```

---

### الحل الإنتاجي: النشر على Play Store

1. ارفع التطبيق على **Play Console** (Internal testing أو Closed testing)
2. ثبّت التطبيق من **متجر Play Store** على الجهاز
3. سيعمل Play Integrity تلقائياً مع الشهادات الصحيحة

---

## تفاصيل تقنية

### كيفية عمل Play Integrity في الكود:

**Dart (lib/services/integrity_service.dart):**
```dart
// يولد nonce فريد لكل طلب
String generateNonce(String prompt) { ... }

// يطلب token من Play Services عبر MethodChannel
Future<String> requestIntegrityToken({required String nonce}) async { ... }
```

**Kotlin (android/app/src/main/kotlin/.../MainActivity.kt):**
```kotlin
val manager = IntegrityManagerFactory.create(applicationContext)
manager.requestIntegrityToken(
    IntegrityTokenRequest.builder()
        .setNonce(nonce)
        .setCloudProjectNumber(cloudProjectNumber)
        .build()
).addOnSuccessListener { result.success(token) }
```

### استجابة Play Integrity النموذجية:

```json
{
  "requestDetails": { "requestPackageName": "com.package.name", ... },
  "accountDetails": { "appLicensingVerdict": "LICENSED" },
  "appIntegrity": {
    "appRecognitionVerdict": "PLAY_RECOGNIZED",
    "certificateSha256Digest": ["6a6a1474b5cbbb2b1aa57e0bc3"],
    "versionCode": "42"
  },
  "deviceIntegrity": {
    "deviceRecognitionVerdict": ["MEETS_DEVICE_INTEGRITY"]
  },
  "testingDetails": { "isTestingResponse": true }
}
```

---

## ملخص سريع

| الوضع | الحل |
|---------|-------|
| **تطوير محلي** | `--dart-define=STRICT_INTEGRITY_CHECK=false` |
| **اختبار على أجهزة حقيقية** | Play Console → App Integrity → Test responses |
| **إنتاج** | نشر على Play Store + تثبيت من المتجر |

---

## ملفات ذات صلة

- `lib/services/integrity_service.dart` - منطق طلب token
- `android/app/src/main/kotlin/.../MainActivity.kt` - تنفيذ Android الأصلي
- `lib/core/app_config.dart` - إعداد `STRICT_INTEGRITY_CHECK`
- `lib/services/ai_proxy_service.dart` - يستدعي خدمة النزاهة
