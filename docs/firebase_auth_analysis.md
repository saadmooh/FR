# تحليل مشكلة مصادقة Firebase مع Google Sign-In

## الوصف
بمجرد إعادة تشغيل أو فتح التطبيق مجدداً، لا يتم حفظ حالة المستخدم ويظهر `currentUser` أو `uid` كـ `null`، مما يُعيد توجيه المستخدم إلى شاشة تسجيل الدخول (`LoginScreen`) في كل مرة بدلاً من البقاء داخل التطبيق.

---

## الملفات والدوال المطلوبة للمراجعة

| الملف | الغرض |
|-------|-------|
| `lib/main.dart` | نقطة بداية التطبيق وتهيئة `WidgetsFlutterBinding` و`Firebase.initializeApp()` |
| `lib/services/auth_service.dart` | دوال `signInWithGoogle`، `signOut`، ومراقب `authStateChanges` |
| `lib/core/app_router.dart` | التوجيه (`redirect`) بناءً على `authService.status` |
| `lib/screens/login_screen.dart` | شاشة تسجيل الدخول |
| `pubspec.yaml` | إصدارات الحزم |

---

## الأخطاء البرمجية المكتشفة

### 1. خطأ حرج: `authService` غير مهيأ مطلقاً

**`lib/main.dart` سطر 48 مقابل سطر 347**

```dart
// سطر 48: مت变量 معلّق بـ late
late AuthService authService;

// ... لا يوجد أي سطر يقوم بـ:
// authService = AuthService();

// سطر 347: يتم تمريره إلى AppRouter وهو غير مهيأ!
appRouter = AppRouter(
  ...
  authService: authService,  // <-- يسبب LateInitializationError
  ...
);
```

هذا يعني أن التطبيق **يسقط** (crash) بمجرد إنشاء `AppRouter`. إذا كان التطبيق يعمل ولكنه يعيد التوجيه إلى Login، فهذا يعني أن هناك شيئاً آخر، لكن هذا الخط وحده كافٍ ليعطل التطبيق.

### 2. حالة `AuthStatus.loading` تمنع التوجيه الصحيح

**`lib/core/app_router.dart` سطر 66-68**

```dart
if (status == AuthStatus.loading) {
  result = null;  // لا يتم التوجيه → يبقى في SplashScreen
}
```

إذا بقي `status` في حالة `loading` لأي سبب، لن يتم التوجيه أبداً. ولكن في الكود الحالي، `AuthService()` يستمع إلى `authStateChanges()` الذي يجب أن يطلق فوراً الحالة الأولية.

### 3. لا يوجد استدعاء `AuthService()` في `_initApp()`

المقارنة بـ `login_screen.dart` سطر 22:

```dart
final user = await AuthService().signInWithGoogle();  // يعمل بسبب الـ singleton
```

ولكن في `main.dart` لا يتم استدعاء `AuthService()` نهائياً قبل تمريره إلى `AppRouter`.

---

## السبب الجذري المحتمل

المشكلة الأساسية هي أن `authService` **لم يتم إنشاء نسخة منه** في دالة `_initApp()`. بدون `authService = AuthService();`:

- لا يتم إنشاء مستمع `authStateChanges()`
- لا يتم تحديث `_status`
- الـ router لا يتلقى أي إشارة `notifyListeners()`
- النتيجة: إما crash (إذا كان `late` محترماً) أو توجيه خاطئ

---

## الإصلاح المطلوب في `main.dart`

أضف سطر إنشاء `AuthService` قبل إنشاء `AppRouter`:

```dart
// في دالة _initApp()، قبل سطر إنشاء AppRouter:
authService = AuthService();  // <-- هذا السطر مفقود تماماً

appRouter = AppRouter(
  ...
  authService: authService,
  ...
);
```

---

## التحقق من الإصلاح

إذا كان التطبيق لا يزال يعيد التوجيه إلى Login بعد الإصلاح أعلاه، تحقق من:

1. **السجلات (logs) من `auth_diag`** — يمكنك فتحها بالضغط المطوّل على شاشة Splash
2. **ما إذا كان `firebase_auth.FirebaseAuth.instance.currentUser` يُرجع `null` فعلاً** في دالة `_initApp()` (سطر 168)
3. **ملف `android/app/build.gradle`** للتحقق من `minSdkVersion` و `google-services.json`
4. **ملف `android/app/src/main/AndroidManifest.xml`** للتحقق من `internet` permission و `SHA-1`

---

## ملاحظات إضافية

- `AuthService` هو `singleton` عبر `factory AuthService() => _instance;`
- `login_screen.dart` يستخدم `AuthService().signInWithGoogle()` ويعمل بدون مشاكل
- `main.dart` هو المكان الوحيد الذي يفشل في إنشاء النسخةSingleton قبل استخدامها

---

## إصدارات الحزم المعنية

من `pubspec.yaml`:

```yaml
firebase_core: ^3.12.1
firebase_auth: ^5.6.0
google_sign_in: ^6.2.2
```

تأكد من أن هذه الإصدارات متوافقة مع بعضها البعض ومع إصدار Firebase SDK المستخدم في `android/build.gradle`.

---

## الخلاصة

المشكلة على الأرجح هي أن `authService = AuthService();` مفقود من `main.dart`. بدون هذا السطر، لا يتم تهيئة حالة المصادقة أبداً، ويبقى التطبيق في حالة لا يملك فيها مستخدماً صالحاً.

---

## المشكلة الخفية: سباق التزامن (Race Condition) عند الإقلاع

حتى بعد إضافة السطر المفقود `authService = AuthService();`، يوجد **ثغرة معمارية خفية شائعة جداً** في تطبيقات Flutter التي تستخدم GoRouter أو `AppRouter` المبني على `Listenable`، وهي السبب الفعلي الذي يجعل التطبيق يرى المستخدم كـ `null` فور الإقلاع بدلاً من مجرد الانهيار:

```text
السبب: الـ Router يقوم بقراءة FirebaseAuth.instance.currentUser بشكل فوري ومتزامن (Synchronous)
النتيجة: الحالة الأولى دائماً null في الإطار الأول (Frame 0)
```

### لماذا يحدث ذلك؟

* بعد استدعاء `Firebase.initializeApp()`، لا يسترجع Firebase Auth الـ Token المحفوظ محلياً بشكل متزامن.
* عملية جلب الـ Token من مساحة التخزين الآمنة للجهاز تأخذ بضعة أجزاء من الثانية.
* خلال تلك الأجزاء، يكون `currentUser == null`.
* يُطلق `authStateChanges()` أول قيمة حقيقية بعد اكتمال القراءة من الـ Cache المحلي، لكن إذا كان الـ Router قد نفذ شرط التوجيه (`redirect`) مبكراً بناءً على الحالة الافتراضية، فسيقرر فوراً أن المستخدم غير مسجل ويحولك إلى `LoginScreen`.

---

## خطوات الإصلاح المعماري الكامل

### 1. تهيئة الـ Singleton وضمان حالته الأولية (`lib/main.dart`)

تأكد من إنشاء النسخة في `_initApp` قبل بناء الـ Router، وانتظر أول بث لحالة المستخدم من الكاش لتفادي الـ Race Condition:

```dart
Future<void> _initApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // تهيئة الخدمة
  authService = AuthService();

  // انتظر أول بث لحالة المستخدم من الكاش لتفادي الـ Race Condition
  await authService.waitForInitialAuth();

  appRouter = AppRouter(
    authService: authService,
    // باقي المعاملات...
  );
}
```

### 2. دعم الانتظار داخل `AuthService` (`lib/services/auth_service.dart`)

داخل كلاس `AuthService`، أضف دالة لانتظار أول قيمة غير معلقة:

```dart
class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;

  AuthStatus _status = AuthStatus.loading;
  AuthStatus get status => _status;

  User? _currentUser;
  User? get currentUser => _currentUser;

  AuthService._internal() {
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      _currentUser = user;
      _status = (user != null) ? AuthStatus.authenticated : AuthStatus.unauthenticated;
      notifyListeners();
    });
  }

  /// ينتظر حتى يقوم Firebase باسترجاع المستخدم من الـ Local Storage
  Future<void> waitForInitialAuth() async {
    if (_status != AuthStatus.loading) return;
    await FirebaseAuth.instance.authStateChanges().first;
  }
}
```

### 3. معالجة `AuthStatus.loading` في الـ Router (`lib/core/app_router.dart`)

تأكد من أن دالة `redirect` تحافظ على بقاء المستخدم في شاشة التحميل طالما أن الحالة ما زالت `AuthStatus.loading`:

```dart
String? redirectLogic(BuildContext context, GoRouterState state) {
  final status = authService.status;
  final isLoggingIn = state.matchedLocation == '/login';
  final isSplash = state.matchedLocation == '/splash';

  // 1. إذا كان Firebase لا يزال يقرأ من الـ Local Cache
  if (status == AuthStatus.loading) {
    return isSplash ? null : '/splash';
  }

  // 2. إذا لم يكن مسجلاً
  if (status == AuthStatus.unauthenticated) {
    return isLoggingIn ? null : '/login';
  }

  // 3. إذا كان مسجلاً ويحاول الدخول لصفحة Login أو Splash
  if (status == AuthStatus.authenticated) {
    if (isLoggingIn || isSplash) {
      return '/home';
    }
  }

  return null;
}
```

---

## قائمة فحص سريعة (Checklist)

- [ ] إضافة `authService = AuthService();` في `main.dart`.
- [ ] التأكد من أن دالة `signOut()` في `google_sign_in` لا يتم استدعاؤها في أي `dispose()` أو `initState()`.
- [ ] التأكد من أن `AppRouter` يستمع لـ `authService` عبر `refreshListenable: authService`.
- [ ] التحقق من أن الـ Router لا يحكم على حالة المستخدم بـ `unauthenticated` طالما أن الحالة لا تزال `loading`.
- [ ] إضافة `await authService.waitForInitialAuth();` قبل إنشاء `AppRouter` في `main.dart`.
- [ ] تحديث `AuthService` لدعم دالة `waitForInitialAuth()` التي تنتظر أول قيمة من `authStateChanges()`.
- [ ] التأكد من أن `redirect` في `AppRouter` لا يُعيد التوجيه إلى `/login` ما دامت الحالة `loading`.

---

## ملاحظات إضافية

- `AuthService` هو `singleton` عبر `factory AuthService() => _instance;`
- `login_screen.dart` يستخدم `AuthService().signInWithGoogle()` ويعمل بدون مشاكل
- `main.dart` هو المكان الوحيد الذي يفشل في إنشاء النسخةSingleton قبل استخدامها
- السبب الخفي: حتى لو تم إنشاء `AuthService`، فإن `FirebaseAuth.instance.currentUser` قد يكون `null` في الإطار الأول بسبب تأخير قراءة Token المحفوظ
- الحل: انتظار `authStateChanges().first` قبل بناء الـ Router
