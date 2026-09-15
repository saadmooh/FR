# تشخيص مشكلة: ظهور واجهة تسجيل الدخول في كل مرة يُفتح فيها التطبيق

## ملاحظة مهمة قبل البداية
التحليل يعتمد على الكود الموجود حالياً في مجلد العمل (`/home/user/myapp`)، مع ملاحظة أن ملف `lib/services/auth_service.dart` يحتوي على **تعديلات غير مكتملة (uncommitted)** مقارنةً بآخر إصدار مكتمل في Git (`546c230`). هذه التعديلات هي جزء أساسي من المشكلة.

---

## 1. الصورة العامة للمشروع

### 1. ما هي حزم المصادقة (auth) المستخدمة في المشروع؟
المشروع يستخدم **4 أنظمة مصادقة تعمل بالتوازي**، كما هو مُعرَّف في `pubspec.yaml`:

| الحزمة | الإصدار | الدور |
|---------|--------|--------|
| `firebase_core` | `^3.12.1` | تهيئة Firebase |
| `firebase_auth` | `^5.6.0` | مصادقة Firebase الأساسية |
| `google_sign_in` | `^6.2.2` | تسجيل الدخول بحساب Google |
| `supabase_flutter` | `^2.16.0` | مصادقة Supabase (كمصادقة ثانوية) |
| `purchases_flutter` | `^10.7.0` | RevenueCat (لإدارة الاشتراكات، وليس مصادقة مباشرة) |

### 2. هل يوجد أكثر من نظام مصادقة يعمل بالتوازي؟
**نعم، يوجد 3 أنظمة مصادقة رئيسية تعمل بالتوازي:**
1. **Firebase Auth** — هو نظام المصادقة الرئيسي
2. **Supabase Auth** — يُستخدم كمصادقة ثانوية، ويتم مزامنته مع Firebase عبر `signInWithIdToken`
3. **Google Sign-In** — يُستخدم كموفر هوية لـ Firebase

**كيف تتم المزامنة:**
- عند تسجيل الدخول الناجح عبر Google، يتم إنشاء مستخدم Firebase
- ثم يتم استخراج `idToken` من Firebase وتمريره إلى Supabase عبر `signInWithIdToken` (`auth_service.dart:86-97`)
- عند بدء التشغيل، إذا كان هناك مستخدم Firebase محفوظ، يتم استعادة جلسة Supabase من خلال `idToken` (`main.dart:184-198`)

### 3. ما هو مسار (route) الشاشة الأولى التي يفتحها main.dart؟
**لا توجد شاشة "Splash" أو "Loading" منفصلة.** التطبيق يبدأ مباشرةً بـ `runApp()` الذي ينشئ `MaterialApp.router` مع `GoRouter`. التوجيه يتم بناءً على حالة المصادقة فوراً.

مسار الشاشة الأولى هو `/` (الرئيسية)، لكن GoRouter يعيد التوجيه فوراً بناءً على `redirect`:
- إذا لم يكن المستخدم مسجلاً الدخول → يُوجَّه إلى `/login`
- إذا كان مسجلاً الدخول ولكن بدون اشتراك premium → يُوجَّه إلى `/paywall`
- إذا كان مسجلاً الدخول و premium → يبقى في `/`

### 4. اعرض محتوى دالة main() كاملة، وأي كود تهيئة (initialization) يُنفَّذ قبل runApp()

`main.dart:70-118` — دالة `main()`:
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  try {
    await _initApp();
  } catch (e, stackTrace) {
    debugPrint('App initialization failed: $e\n$stackTrace');
    runApp(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF1A1A2E),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 64),
                  const SizedBox(height: 16),
                  const Text(
                    'Failed to start app',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    e.toString(),
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return;
  }
}
```

الكود الذي يُنفَّذ قبل `runApp()` موجود في `_initApp()` (`main.dart:159-347`):
1. `await Firebase.initializeApp()` — تهيئة Firebase
2. `await Supabase.initialize(...)` — تهيئة Supabase
3. `authService = AuthService()` — إنشاء خدمة المصادقة
4. `await authService.initialAuthState` — **انتظار حالة المصادقة الأولية**
5. `revenueCatService = RevenueCatService()` — إنشاء خدمة RevenueCat
6. `await revenueCatService.initialize()` — تهيئة RevenueCat
7. استعادة جلسة Supabase من Firebase (إذا كان المستخدم مسجلاً الدخول)
8. ربط RevenueCat بهوية Firebase
9. تهيئة ObjectBox و SharedPreferences
10. تهيئة الخدمات الأخرى (إشعارات، AI، إلخ)
11. إنشاء `AppRouter`
12. `runApp(FlexReminderApp(...))`

---

## 2. تخزين واستعادة الجلسة (Session Persistence)

### 5. أين يتم تخزين بيانات الجلسة/التوكن محليًا؟
**Firebase Auth** يستخدم تخزينه الداخلي الخاص:
- على **Android**: يُخزَّن في `SharedPreferences` الخاص بـ Firebase (داخل مجلد التطبيق)
- على **iOS**: يُخزَّن في **Keychain**

**Supabase Auth** أيضاً يستخدم تخزينه الداخلي (عادةً `SharedPreferences` على Android، `Keychain` على iOS).

**Pro Session JWT** (للـ AI Proxy) يُخزَّن في `flutter_secure_storage` (`session_token_service.dart:36`):
```dart
final FlutterSecureStorage _storage = const FlutterSecureStorage();
```

**إعدادات التطبيق** تُخزَّن في `SharedPreferences` (`app_settings_repository.dart:13`).

**مفتاح API** يُخزَّن في `flutter_secure_storage` مع نسخة احتياطية في `SharedPreferences` (`api_credential_store.dart:11-45`).

### 6. هل يتم استدعاء أي دالة لاستعادة الجلسة عند بدء التشغيل؟
**نعم، ولكن بطريقة غير موثوقة:**

1. **Firebase Auth**: لا يتم استدعاء دالة استعادة صريحة. Firebase يُعرِّف الجلسة تلقائياً عند `Firebase.initializeApp()`. لكن الكود الحالي ينتظر `authService.initialAuthState` (`main.dart:180`).

2. **Supabase Auth**: يتم الاستعادة يدوياً في `main.dart:184-198`:
```dart
if (AppConfig.isSupabaseConfigured && authService.currentUser != null) {
  try {
    final idToken = await authService.currentUser!.getIdToken();
    if (idToken != null) {
      await Supabase.instance.client.auth.signInWithIdToken(
        provider: OAuthProvider('custom:firebase'),
        idToken: idToken,
      );
      debugPrint('Supabase session restored from Firebase user');
    }
  } catch (e) {
    debugPrint('Failed to restore Supabase session: $e');
  }
}
```

3. **RevenueCat**: يتم الربط في `main.dart:202-205`:
```dart
final rcFirebaseUser = authService.currentUser;
if (rcFirebaseUser != null) {
  await revenueCatService.linkToUser(rcFirebaseUser.uid);
}
```

### 7. هل التخزين المحلي يعمل بشكل غير متزامن (async)؟ هل هناك احتمال أن واجهة تسجيل الدخول تُبنى قبل انتهاء قراءة التوكن من التخزين (race condition)؟
**نعم، يوجد احتمال كبير لحدوث race condition:**

Firebase Auth يُعرِّف الجلسة بشكل غير متزامن. `FirebaseAuth.instance.currentUser` قد يكون `null` مباشرة بعد `Firebase.initializeApp()` لأن Firebase لا يزال يقرأ الجلسة المحفوظة من التخزين.

في `auth_service.dart:15-28`:
```dart
AuthService._internal() {
  _authStateSubscription = _auth.authStateChanges().listen((user) {
    if (!_initialAuthStateComplete.isCompleted) {
      _initialAuthStateComplete.complete(user);
    }
    notifyListeners();
  });

  Future.delayed(const Duration(milliseconds: 500), () {
    if (!_initialAuthStateComplete.isCompleted) {
      _initialAuthStateComplete.complete(_auth.currentUser);
    }
  });
}
```

المشكلة هنا هي **الـ 500ms fallback**. إذا لم يُصدِر `authStateChanges()` القيمة خلال 500ms (وهذا شائع عند بدء التشغيل البارد حيث يقرأ Firebase الجلسة من القرص)، فإن الـ fallback يُكمِّل `_initialAuthStateComplete` بقيمة `_auth.currentUser`. إذا كانت Firebase لا تزال تُعرِّف الجلسة، فإن `_auth.currentUser` سيكون `null`.

ثم في `main.dart:180`:
```dart
await authService.initialAuthState;
```

يُكمِّل هذا بانتظار القيمة `null`. ي proceed الكود مع `currentUser == null`. ثم في `main.dart:185`:
```dart
if (AppConfig.isSupabaseConfigured && authService.currentUser != null) {
```

هذا الشرط يفشل، فلا يتم استعادة جلسة Supabase. ثم يُبنى التطبيق ويُوجَّه Router إلى `/login`.

### 8. هل تم اختبار قراءة التخزين المحلي يدويًا؟
**لا يوجد كود اختبار صريح في الكود لفحص ما إذا كان التوكن موجوداً بعد إغلاق التطبيق.** لا توجد `print`/`debugPrint` messages تتحقق من وجود الجلسة المحفوظة عند بدء التشغيل.

### 9. في حالة استخدام flutter_secure_storage: هل توجد أي إعدادات خاصة قد تمسح البيانات؟
**نعم، ولكن لـ Pro Session JWT فقط، وليس لـ Firebase/Supabase:**
- `flutter_secure_storage` يُستخدم في `session_token_service.dart` و `api_credential_store.dart`
- لا يوجد إعداد `resetOnError` أو ما شابه في الكود
- لكن `flutter_secure_storage` على Android قد يمسح البيانات في حالات معينة (مثل إعادة تعيين التطبيق أو تغيير كلمة المرور)

---

## 3. حالة المصادقة (Auth State) وإدارة الحالة (State Management)

### 10. ما هو حل إدارة الحالة المستخدم؟
**مزيج من:**
1. **ChangeNotifier** — لـ `AuthService` و `RevenueCatService`
2. **ValueNotifier** — للقيم العامة مثل `pendingSharedUrl` و `aiRescheduleError` و `reminderOpenedId`
3. **GoRouter refreshListenable** — لربط تغييرات الحالة بالتوجيه
4. **setState** — داخل الـ Widgets

### 11. هل يوجد Stream/Listener يستمع لتغيّر حالة المستخدم؟
**نعم، في `auth_service.dart:16-21`:**
```dart
_authStateSubscription = _auth.authStateChanges().listen((user) {
  if (!_initialAuthStateComplete.isCompleted) {
    _initialAuthStateComplete.complete(user);
  }
  notifyListeners();
});
```

يبدأ الاستماع **في المُنشئ (constructor)** الخاص بـ `AuthService` (`auth_service.dart:15`)، أي قبل `runApp()`.

### 12. هل يُحتمل أن يكون هناك اشتراك جديد (listener) يُنشأ في كل مرة تُعاد بناء الواجهة (rebuild)؟
**لا، الـ listener يُنشأ مرة واحدة فقط** عند إنشاء `AuthService` (الذي هو singleton). لا يتم إعادة إنشائه عند إعادة بناء الواجهة.

لكن هناك مشكلة أخرى: `AuthService` هو singleton، ويُستدعى `AuthService()` في عدة أماكن (مثل `login_screen.dart:22` و `main.dart:179`). بما أنه singleton، فإن المُنشئ يُستدعى مرة واحدة فقط، والـ listener يُضاف مرة واحدة فقط. هذا صحيح.

### 13. ما هي القيمة الافتراضية (initial state) لحالة المستخدم قبل تحميل الجلسة؟
**لا توجد قيمة "loading" منفصلة.** القيمة الافتراضية هي `null` (غير مسجل دخول).

في `auth_service.dart:36-37`:
```dart
firebase_auth.User? get currentUser => _auth.currentUser;
bool get isSignedIn => _auth.currentUser != null;
```

لا يوجد `enum AuthStatus { loading, authenticated, unauthenticated }` أو ما شابه. الحالة هي إما `null` (غير مسجل) أو كائن `User` (مسجل).

### 14. هل هناك تفريق واضح في الكود بين ثلاث حالات: (تحميل / مسجل دخول / غير مسجل دخول)؟
**لا، لا يوجد تفريق واضح.** الكود يعامل الحالتين "loading" و "unauthenticated" بنفس الطريقة: `isSignedIn` يكون `false` في كلتا الحالتين.

في `app_router.dart:57-66`:
```dart
redirect: (context, state) {
  final isLoggedIn = authService.isSignedIn;
  ...
  if (!isLoggedIn) {
    return isOnLogin ? null : '/login';
  }
  ...
}
```

إذا كان `isSignedIn == false` (سواء لأنه `loading` أو `unauthenticated`)، يُوجَّه إلى `/login`. لا توجد شاشة تحميل منفصلة.

---

## 4. Firebase / Supabase تحديدًا

### 15. هل تم استدعاء Firebase.initializeApp() بالكامل (مع await) قبل أي محاولة لقراءة FirebaseAuth.instance.currentUser؟
**نعم، ولكن مع مشكلة:**

في `main.dart:160`:
```dart
await Firebase.initializeApp();
```

ثم في `main.dart:179-180`:
```dart
authService = AuthService();
await authService.initialAuthState;
```

`Firebase.initializeApp()` يُستدعى أولاً. لكن `AuthService()` يُنشأ بعده مباشرة، والمُنشئ يبدأ الاستماع لـ `authStateChanges()`. المشكلة هي أن `_auth.currentUser` قد يكون `null` حتى بعد `Firebase.initializeApp()` لأن Firebase Auth يُعرِّف الجلسة بشكل غير متزامن.

### 16. بالنسبة لـ Supabase: هل تم استدعاء Supabase.initialize() مع انتظار اكتماله، وهل persistSession مفعّل صراحة في الإعدادات؟
**نعم، `Supabase.initialize()` يُستدعى مع `await`** (`main.dart:165`):
```dart
await Supabase.initialize(
  url: AppConfig.supabaseUrl,
  publishableKey: AppConfig.supabaseAnonKey,
);
```

**لكن `persistSession` غير مفعّل صراحة.** في إصدار `supabase_flutter ^2.16.0`، `persistSession` مفعّل افتراضياً (قيمته `true`)، لكن عدم تمريره صراحة قد يسبب مشاكل في بعض الإصدارات أو المنصات.

### 17. هل يوجد استخدام لـ Purchases.logIn() أو أي مكتبة طرف ثالث أخرى قد تعيد ضبط حالة المستخدم؟
**نعم، `Purchases.logIn()` يُستدعى في `revenuecat_service.dart:116`:**
```dart
final result = await Purchases.logIn(firebaseUid);
```

هذا يُستدعى فقط عند ربط RevenueCat بهوية Firebase (ليس عند بدء التشغيل). لا يُعتقد أنه يعيد ضبط حالة المستخدم.

### 18. هل توجد أي دالة signOut() تُستدعى تلقائيًا أو بالخطأ عند بدء التشغيل؟
**لا، لا يوجد استدعاء تلقائي لـ `signOut()` عند بدء التشغيل.** `signOut()` يُستدعى فقط من `settings_screen.dart:171` عند نقر المستخدم على "تسجيل الخروج".

### 19. هل التوكن المخزّن منتهي الصلاحية (expired) ولا يوجد كود لتجديده؟
**Firebase Auth يُجدد التوكن تلقائياً.** لا يوجد كود صريح لـ `refreshSession` في التطبيق. Firebase Auth يعالج انتهاء الصلاحية تلقائياً عبر `authStateChanges()`.

لكن المشكلة هي أن `authStateChanges()` قد يُصدِر `null` أولاً أثناء التجديد، ثم يُصدِر المستخدم لاحقاً. في الكود الحالي، الإصدار الأول `null` يُكمِّل `_initialAuthStateComplete` بقيمة `null`، مما يسبب المشكلة.

---

## 5. دورة حياة التطبيق (App Lifecycle) ومنصة التشغيل

### 20. هل المشكلة تحدث على: أندرويد فقط، iOS فقط، ويندوز، أم الكل؟
**الكود الحالي لا يحدد المنصة، لكن:**
- `flutter_secure_storage` يُستخدم على جميع المنصات
- Firebase Auth يعمل على Android و iOS و Web
- لا يوجد كود خاص بمنصة واحدة يمسح الجلسة

### 21. هل تم اختبار الفرق بين: إغلاق التطبيق كليًا (kill) وإعادة فتحه، مقابل وضعه في الخلفية (background) ثم إرجاعه (resume)؟
**لا يوجد كود اختبار صريح.** لكن:
- عند `resume`، يتم استدعاء `_runOverdueCheck()` (`main.dart:437`)
- لا يوجد كود يمسح الجلسة عند `paused` أو `detached`

### 22. هل هناك أي كود يتفاعل مع AppLifecycleState قد يمسح بيانات الجلسة؟
**لا.** في `main.dart:430-445`:
```dart
void didChangeAppLifecycleState(AppLifecycleState state) async {
  switch (state) {
    case AppLifecycleState.paused:
    case AppLifecycleState.detached:
      // Store stays open for the entire process lifetime
      break;
    case AppLifecycleState.resumed:
      await _runOverdueCheck();
      ...
      break;
    default:
      break;
  }
}
```

لا يوجد مسح للجلسة عند `paused` أو `detached`.

### 23. إذا كان تطبيق ويندوز/سطح مكتب: هل تخزين الجلسة يعتمد على مسار ملفات قد يتغير؟
**التطبيق موجه للأندرويد أساساً** (كما هو مذكور في `AGENTS.md`). لا يوجد كود خاص بـ Windows.

---

## 6. الأخطاء والسجلات (Logs)

### 24. هل توجد رسائل خطأ أو تحذيرات في console عند بدء التشغيل مرتبطة بالمصادقة أو التخزين المحلي؟
**لا توجد رسائل خطأ صريحة في الكود.** لكن يمكن إضافة `debugPrint` لتتبع المشكلة.

### 25. هل تمت إضافة أي print/debugPrint/log مؤقت لتتبع قيمة التوكن أو حالة المستخدم عند بدء التشغيل؟
**لا توجد تتبعات صريحة لحالة المصادقة عند بدء التشغيل.** يمكن إضافة:
```dart
debugPrint('Firebase currentUser at startup: ${_auth.currentUser?.uid ?? "null"}');
debugPrint('Auth state initial: ${authService.currentUser?.uid ?? "null"}');
```

---

## 7. تغييرات حديثة

### 26. هل حدث أي تغيير مؤخرًا في: مكتبة المصادقة، منطق التخزين المحلي، أو شاشة البداية؟
**نعم، التعديلات غير المكتملة (uncommitted) في `auth_service.dart` هي التغيير الرئيسي:**

الملف `auth_service.dart` يحتوي على تعديلات غير مكتملة أضافت:
1. `ChangeNotifier` extension
2. `_initialAuthStateComplete` Completer
3. 500ms fallback
4. `notifyListeners()` في `authStateChanges()` listener

هذه التعديلات غير موجودة في آخر إصدار مكتمل (`546c230`).

### 27. هل تم اختبار هذه المشكلة على نسخة نظيفة (uninstall/reinstall)؟
**لا يوجد كود اختبار صريح.** لكن يمكن اختبار:
1. إلغاء تثبيت التطبيق
2. تثبيته من جديد
3. تسجيل الدخول
4. إغلاق التطبيق تماماً
5. إعادة فتحه
6. التحقق مما إذا كانت الشاشة تظهر

---

## 8. الخلاصة المطلوبة

### السبب الجذري الأرجح

السبب الجذري هو **Race condition في `AuthService` ناتج عن الـ 500ms fallback**، مقترناً **بعدم وجود حالة "loading" منفصلة** في Router.

**التسلسل الزمني للمشكلة:**

1. `main.dart:160` — `await Firebase.initializeApp()` يُستدعى
2. `main.dart:179` — `authService = AuthService()` يُنشأ
3. `auth_service.dart:15-28` — المُنشئ يبدأ الاستماع لـ `authStateChanges()` ويضبط 500ms fallback
4. Firebase Auth يبدأ تحميل الجلسة من التخزين (عملية غير متزامنة)
5. `main.dart:180` — `await authService.initialAuthState` ينتظر
6. إذا لم يُصدِر `authStateChanges()` القيمة خلال 500ms (حالة شائعة في بدء التشغيل البارد):
   - الـ fallback يُكمِّل `_initialAuthStateComplete` بقيمة `_auth.currentUser`
   - إذا كانت Firebase لا تزال تُعرِّف الجلسة، `_auth.currentUser` يكون `null`
7. `main.dart:185` — الشرط `authService.currentUser != null` يفشل
8. `main.dart:202` — الشرط `rcFirebaseUser != null` يفشل
9. التطبيق ي proceed مع `currentUser == null`
10. GoRouter يُقيِّم `redirect` ويرى `isLoggedIn == false`
11. يُوجَّه إلى `/login`
12. لاحقاً، Firebase يُعرِّف الجلسة ويُصدِر `authStateChanges()` بقيمة المستخدم
13. `notifyListeners()` يُستدعى، لكن GoRouter قد لا يعيد التوجيه بشكل صحيح إذا كان المستخدم بالفعل على `/login`

**السبب الثانوي المحتمل:**
- إذا كان `authStateChanges()` يُصدِر `null` أولاً (أثناء تجديد التوكن)، فإن `_initialAuthStateComplete` يُكمَّل بقيمة `null` فوراً. ثم عندما يُصدِر المستخدم لاحقاً، GoRouter يعيد التوجيه، لكن المستخدم قد يكون قد رأى شاشة تسجيل الدخول بالفعل.

### اسم الملف والسطر بالضبط

المشكلة الرئيسية في:
- **`lib/services/auth_service.dart:22-27`** — الـ 500ms fallback
- **`lib/services/auth_service.dart:16-21`** — `authStateChanges()` listener يكمل `_initialAuthStateComplete` بأول قيمة يُصدِرها (قد تكون `null`)
- **`lib/core/app_router.dart:58`** — `isSignedIn` يقرأ `_auth.currentUser` مباشرة بدون حالة تحميل
- **`lib/core/app_router.dart:64-66`** — منطق التوجيه لا يميز بين "loading" و "unauthenticated"
- **`lib/main.dart:180`** — `await authService.initialAuthState` ينتظر القيمة التي قد تكون `null`

### الإصلاح المقترح

**الخيار 1 (الأفضل): إزالة الـ 500ms fallback والاعتماد على `authStateChanges()` فقط**

في `lib/services/auth_service.dart`:
```dart
AuthService._internal() {
  _authStateSubscription = _auth.authStateChanges().listen((user) {
    if (!_initialAuthStateComplete.isCompleted) {
      _initialAuthStateComplete.complete(user);
    }
    notifyListeners();
  });
  // Remove the 500ms fallback entirely
}
```

ثم في `lib/main.dart`، لا تنتظر `initialAuthState` مباشرة. بدلاً من ذلك، اسمح لـ `authStateChanges()` بالعمل، واجعل Router يعرض شاشة تحميل حتى يُصدَر المستخدم.

**الخيار 2: إضافة حالة "loading" منفصلة**

أضف `enum AuthStatus { loading, authenticated, unauthenticated }` إلى `AuthService`، واجعل Router يعرض شاشة تحميل عندما تكون الحالة `loading`.

**الخيار 3 (الأسرع): إزالة `await authService.initialAuthState` من `main.dart`**

في `lib/main.dart:180`، احذف:
```dart
await authService.initialAuthState;
```

واترك `AuthService` يعمل بشكل طبيعي. `authStateChanges()` سيُصدِر المستخدم تلقائياً عندما تكون الجلسة مُعرِّفَة، و `notifyListeners()` سيُحدِّث Router.

لكن هذا الخيار قد يسبب مشكلة إذا كان هناك كود يعتمد على `currentUser` فوراً بعد إنشاء `AuthService` (مثل استعادة Supabase في `main.dart:185`).

**الخيار 4 (موصى به):combine الخيار 1 + إصلاح منطق التوجيه**

1. أزل الـ 500ms fallback من `auth_service.dart`
2. أزل `await authService.initialAuthState` من `main.dart`
3. أضف حالة `loading` إلى `AuthService`
4. في Router، إذا كانت الحالة `loading`، اعرض شاشة تحميل بدلاً من التوجيه إلى `/login`

هذا يضمن أن التطبيق لا يوجه إلى `/login` حتى تتأكد من أن Firebase Auth قد انتهى من تعريف الجلسة.

---

## التوصية النهائية

السبب الجذري هو **الـ 500ms fallback في `auth_service.dart:22-27`** الذي يكمل `_initialAuthStateComplete` بقيمة `null` قبل انتهاء Firebase Auth من تعريف الجلسة المحفوظة.

الإصلاح الموصى به هو **إزالة الـ 500ms fallback** والاعتماد على `authStateChanges()` فقط، مع إضافة حالة `loading` منفصلة في Router لمنع التوجيه المبكر إلى `/login`.
