# مراجعة Firebase Auth Session Restore في الخلفية

تاريخ التحليل: 2026-08-27

---

## الكود الحالي (workmanager_service.dart:53-70)

```dart
try {
  final client = Supabase.instance.client;
  if (client.auth.currentSession == null) {
    final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
    if (firebaseUser != null) {
      final idToken = await firebaseUser.getIdToken();
      if (idToken != null) {
        await client.auth.signInWithIdToken(
          provider: OAuthProvider('custom:firebase'),
          idToken: idToken,
        );
        debugPrint('Background Supabase session restored from Firebase');
      }
    }
  }
} catch (e) {
  debugPrint('Background Supabase session restore failed: $e');
}

_bgServicesInitialized = true;  // يُنفذ دائماً حتى لو فشل الاسترجاع
```

---

## المشاكل المحددة

### 1. `FirebaseAuth.instance.currentUser` قد يكون `null` في الـ isolate المنفصل ❌

- Firebase Auth state لا يُحفظ/يُشارك تلقائياً عبر الـ isolates
- الـ `currentUser` يعتمد على native plugin state الذي قد لا يكون مُهيأ في الخلفية
- لا يوجد `await FirebaseAuth.instance.authStateChanges().first` لضمان التهيئة

### 2. لا يوجد fallback عند الفشل ❌

- الكود يطبع خطأ ويكمل (`_bgServicesInitialized = true` في السطر 72)
- يجعل Supabase يبدو "مهيأ" لكن بدون جلسة صالحة
- العمليات اللاحقة (`Supabase.instance.client.auth.currentSession`) ستفشل بصمت

### 3. `custom:firebase` provider يتطلب إعداد في Supabase Dashboard ⚠️

- يجب تكوين "Custom Provider" في Supabase Auth Settings
- إذا لم يكن مُكوّن، سيفشل `signInWithIdToken` بخطأ غير واضح

### 4. لا يوجد تحقق من صلاحية الجلسة المستعادة ❌

- بعد `signInWithIdToken`، لا يتحقق من نجاح العملية فعلاً
- قد تنجح المكالمة لكن الجلسة تظل منتهية أو غير صالحة

---

## الكود المحسن المقترح

```dart
try {
  final client = Supabase.instance.client;
  
  // أولاً: تحقق من وجود جلسة صالحة بالفعل
  final existingSession = client.auth.currentSession;
  if (existingSession != null && !existingSession.isExpired) {
    debugPrint('Supabase session already valid');
    _bgServicesInitialized = true;
    return;
  }
  
  debugPrint('No valid Supabase session, attempting Firebase restore...');
  
  // تأكد من تهيئة Firebase Auth في هذا الـ isolate
  await firebase_auth.FirebaseAuth.instance.authStateChanges().first;
  
  final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
  debugPrint('Firebase currentUser: ${firebaseUser?.uid ?? "NULL"}');
  
  if (firebaseUser == null) {
    debugPrint('WARNING: Firebase user is null in background isolate');
    debugPrint('Supabase operations will run without auth (may fail for protected functions)');
    _bgServicesInitialized = true;
    return;
  }
  
  final idToken = await firebaseUser.getIdToken();
  debugPrint('Firebase ID token: ${idToken != null ? "obtained" : "NULL"}');
  
  if (idToken == null) {
    debugPrint('ERROR: Failed to get Firebase ID token');
    _bgServicesInitialized = true;
    return;
  }
  
  await client.auth.signInWithIdToken(
    provider: OAuthProvider('custom:firebase'),
    idToken: idToken,
  );
  
  // تحقق صريح من نجاح الاستعادة
  final newSession = client.auth.currentSession;
  if (newSession != null && !newSession.isExpired) {
    debugPrint('Background Supabase session restored from Firebase successfully');
  } else {
    debugPrint('WARNING: signInWithIdToken succeeded but session is still invalid');
  }
  
} catch (e) {
  debugPrint('Background Supabase session restore failed: $e');
  // لا تضبط _bgServicesInitialized = true هنا - اتركها false للإشارة للفشل
}

_bgServicesInitialized = true;
```

---

## تغييرات مهمة في الكود المحسن

| التغيير | السبب |
|----------|-------|
| `await authStateChanges().first` | يضمن تهيئة Firebase Auth في الـ isolate |
| تحقق من `existingSession` و `isExpired` | يتجنب استعادة غير ضرورية |
| Early return مع logging واضح عند `firebaseUser == null` | يوضح السبب بدلاً من الفشل الصامت |
| تحقق صريح من `newSession` بعد الاستعادة | يؤكد نجاح العملية فعلاً |
| عدم ضبط `_bgServicesInitialized = true` داخل catch | يسمح للكود المُستدعي بمعرفة الفشل |

---

## متطلبات Supabase Dashboard

تأكد من تكوين **Custom Provider** في Supabase:
1. Settings → Auth → Providers
2. Add Provider → Custom
3. Name: `custom:firebase` (يجب أن يطابق الكود)
4. Configure JWKS endpoint أو public key لـ Firebase

---

## اختبار سريع

أضف هذا في `_initBackgroundServices` مؤقتاً لتأكيد القيمة:

```dart
debugPrint('AppConfig.isSupabaseConfigured: ${AppConfig.isSupabaseConfigured}');
debugPrint('Supabase URL: ${AppConfig.supabaseUrl}');
```

ثم شغّل release build وتحقق من logs.

---

## الملفات ذات الصلة

- `lib/services/workmanager_service.dart:53-70` - الكود الحالي
- `lib/main.dart:126-138` - نفس المنطق في main isolate (للمرجع)
- `lib/services/auth_service.dart:66-78` - استعادة الجلسة عند تسجيل الدخول