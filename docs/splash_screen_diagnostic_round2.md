# تشخيص أعمق لمشكلة التوقف عند شاشة Splash — الجولة الثانية

## السؤال 0 — الفاصل الحاسم

### هل السبينر الظاهر هو ودجت فلاتر `SplashScreen`، أم الشاشة الأصلية للنظام؟

بناءً على الكود الحالي، **الودجت الظاهر هو `SplashScreen` الخاص بفلاتر** (الأيقونة + "Bookmark Reminder" + السبينر الصغير)، وليس الشاشة الأصلية للنظام.

**السبب:** `_initApp()` في `lib/main.dart` يُستدعى **قبل** `runApp()` فقط عند البداية الباردة (cold start). إذا توقفت `_initApp()` تماماً، فلن يتم استدعاء `runApp()` ولن يظهر `SplashScreen`. بما أن السؤال يشير إلى أن السبينر **لا يتوقف** (أي أن الودجت يظهر)، فهذا يعني:

- ✅ `_initApp()` اكتملت بنجاح و`runApp()` تم استدعاؤه.
- ✅ `GoRouter` يعمل ويعرض `/` كـ `SplashScreen`.
- ❌ **المشكلة إذًا في منطق `redirect` في `GoRouter`**، وليست في `_openMainStore()` أو RevenueCat مباشرة.

هذا يلغي الاحتمالين الأول والثاني من التحليل السابق، ويؤكد أن المشكلة في **الاحتمال الثالث** (منطق `redirect`).

---

## إذا كانت المشكلة في `redirect` (ودجت فلاتر ظاهر):

### 1. الكود الكامل لـ `AuthService`

**الملف:** `lib/services/auth_service.dart`

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import '../core/app_config.dart';
import 'package:gotrue/gotrue.dart' show OAuthProvider;
import 'revenuecat_service.dart';

enum AuthStatus { loading, authenticated, unauthenticated }

class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;

  AuthService._internal() {
    // Set initial status immediately from currentUser (works on cold start and resume)
    _status = _auth.currentUser != null
        ? AuthStatus.authenticated
        : AuthStatus.unauthenticated;
    if (!_initialAuthStateComplete.isCompleted) {
      _initialAuthStateComplete.complete(_auth.currentUser);
    }
    notifyListeners();

    _authStateSubscription = _auth.authStateChanges().listen((user) {
      _status = user != null
          ? AuthStatus.authenticated
          : AuthStatus.unauthenticated;
      if (!_initialAuthStateComplete.isCompleted) {
        _initialAuthStateComplete.complete(user);
      }
      if (user != null) {
        unawaited(_restoreExternalSessions(user));
      }
      notifyListeners();
    });
  }

  final firebase_auth.FirebaseAuth _auth = firebase_auth.FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId:
        '1038373651011-aajl0k8goi5hknl4l0sqsnb78m7lnrfj.apps.googleusercontent.com',
  );

  firebase_auth.User? get currentUser => _auth.currentUser;
  bool get isSignedIn => _auth.currentUser != null;
  AuthStatus _status = AuthStatus.loading;
  AuthStatus get status => _status;

  StreamSubscription<firebase_auth.User?>? _authStateSubscription;
  final Completer<firebase_auth.User?> _initialAuthStateComplete =
      Completer<firebase_auth.User?>();

  Future<firebase_auth.User?> get initialAuthState =>
      _initialAuthStateComplete.future;

  Future<firebase_auth.User?> signInWithGoogle() async {
    try {
      GoogleSignInAccount? googleUser = await _googleSignIn.signInSilently();
      googleUser ??= await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = firebase_auth.GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final firebase_auth.UserCredential userCredential =
          await _auth.signInWithCredential(credential);
      final user = userCredential.user;

      // RevenueCat linking + Supabase session sync run in the background so
      // navigation is never blocked by slow network calls. The router picks
      // up the premium status via revenueCatService's notifyListeners.
      if (user != null) {
        unawaited(_postSignInSync(user));
      }

      return user;
    } catch (e) {
      debugPrint('Google sign-in failed: $e');
      return null;
    }
  }

  Future<void> _postSignInSync(firebase_auth.User user) async {
    try {
      await RevenueCatService().linkToUser(user.uid);
    } catch (e) {
      debugPrint('RevenueCat link failed: $e');
    }

    if (!AppConfig.isSupabaseConfigured) return;
    try {
      final idToken = await user.getIdToken();
      if (idToken != null) {
        await supabase.Supabase.instance.client.auth.signInWithIdToken(
          provider: const OAuthProvider('custom:firebase'),
          idToken: idToken,
        );
        debugPrint('Supabase sign-in successful');
      }
    } catch (e) {
      debugPrint('Supabase sign-in failed: $e');
    }
  }

  Future<void> _restoreExternalSessions(firebase_auth.User user) async {
    await _postSignInSync(user);
  }

  Future<void> signOut() async {
    try {
      await RevenueCatService().logout();
      await _googleSignIn.signOut();
      await _auth.signOut();
      if (AppConfig.isSupabaseConfigured) {
        await supabase.Supabase.instance.client.auth.signOut();
      }
    } catch (e) {
      debugPrint('Sign-out failed: $e');
    }
  }

  Future<void> deleteAccount() async {
    try {
      await _auth.currentUser?.delete();
      await _googleSignIn.signOut();
      if (AppConfig.isSupabaseConfigured) {
        await supabase.Supabase.instance.client.auth.signOut();
      }
    } catch (e) {
      debugPrint('Account deletion failed: $e');
      rethrow;
    }
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel();
    super.dispose();
  }
}
```

**القيمة الافتراضية لـ `status`:** `AuthStatus.loading` (السطر 49).
**متى يتغير:** فوراً في البناء (`AuthService._internal()`) بناءً على `_auth.currentUser != null`، ثم تلقائياً عند أي تغيير في `authStateChanges()`.

### 2. هل تعتمد على `Stream` أم `Future`؟

تعتمد على **`Stream`** من `authStateChanges()`.

**الترتيب:** في `AuthService._internal()`:
1. يُعين `_status` فوراً بناءً على `currentUser` (السطر 19-21).
2. يُستدعى `notifyListeners()` (السطر 25).
3. **ثم** يشترك في `authStateChanges()` (السطر 27).

إذن `notifyListeners()` الأول يُستدعى **قبل** اشتراك الـ Stream، لكن هذا ليس مشكلة لأن القيمة الأولية صحيحة بالفعل.

### 3. هل يوجد تايمر fallback؟

**لا،** لا يوجد تايمر fallback في `auth_service.dart` حالياً. الحالة تتغير فوراً بناءً على `currentUser` أو عبر `authStateChanges()`.

### 4. Supabase مشروط بـ `AppConfig.isSupabaseConfigured`

في `main.dart`:
```dart
if (AppConfig.isSupabaseConfigured) {
  try {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );
  } catch (e) {
    debugPrint('Supabase initialization failed: $e');
    if (initError == null) initError = 'Supabase initialization failed: $e';
  }
}
```

في `auth_service.dart`، إذا كان Supabase **غير مهيأ**، فإن `_postSignInSync()` يتوقف عند:
```dart
if (!AppConfig.isSupabaseConfigured) return;
```

لكن هناك **مشكلة محتملة** في `signOut()`:
```dart
Future<void> signOut() async {
  try {
    await RevenueCatService().logout();
    await _googleSignIn.signOut();
    await _auth.signOut();
    if (AppConfig.isSupabaseConfigured) {  // ✅ محمي
      await supabase.Supabase.instance.client.auth.signOut();
    }
  } catch (e) {
    debugPrint('Sign-out failed: $e');
  }
}
```

هذا محمي جيداً. لا يوجد استثناء صامت يمنع `notifyListeners()`.

### 5. الكود الكامل لـ `RevenueCatService` — الجزء المسؤول عن `isPremium`

**الملف:** `lib/services/revenuecat_service.dart`

```dart
class RevenueCatService extends ChangeNotifier {
  static final RevenueCatService _instance = RevenueCatService._internal();
  factory RevenueCatService() => _instance;
  RevenueCatService._internal();

  static const String _apiKey = 'goog_LfeTyBNEEqcHhnhRvnlRlzIvwbu';

  Offerings? _offerings;
  CustomerInfo? _customerInfo;
  bool _isPremium = false;  // ⚠️ القيمة الافتراضية: false

  bool get isPremium => _isPremium;
  Offerings? get offerings => _offerings;

  void _refreshSessionToken() {
    if (!_isPremium) return;
    unawaited(() async {
      try {
        await SessionTokenService.instance.refresh();
      } catch (e) {
        debugPrint('Session token refresh failed: $e');
      }
    }());
  }

  Future<void> initialize() async {
    await Purchases.setLogLevel(LogLevel.debug);
    await Purchases.configure(PurchasesConfiguration(_apiKey));

    debugPrint('App User ID: ${await Purchases.appUserID}');
    debugPrint('Is Anonymous: ${await Purchases.isAnonymous}');
    showUiLog(
      'RC User: ${await Purchases.appUserID}\n'
      'Anonymous: ${await Purchases.isAnonymous}',
      duration: const Duration(seconds: 6),
    );

    try {
      _customerInfo = await Purchases.getCustomerInfo();  // ⚠️ بدون timeout!
      _updatePremiumStatus();
    } catch (e) {
      debugPrint('Failed to get customer info: $e');
    }

    Purchases.addCustomerInfoUpdateListener((customerInfo) {
      _customerInfo = customerInfo;
      _updatePremiumStatus();
    });
  }

  void _updatePremiumStatus() {
    final entitlements = _customerInfo?.entitlements;
    debugPrint('All entitlements: ${entitlements?.all}');
    debugPrint('Active entitlements: ${entitlements?.active}');
    _isPremium =
        entitlements?.active.containsKey(AppConstants.premiumEntitlementId) ??
            false;
    debugPrint('Premium status: $_isPremium');
    showUiLog(
      'RC Active: ${entitlements?.active.keys.toList() ?? []} | '
      'Premium: $_isPremium',
      duration: const Duration(seconds: 4),
    );
    notifyListeners();  // ✅ يتم استدعاؤه
  }
```

**القيمة الافتراضية لـ `isPremium`:** `false`.
**هل تمتد من `ChangeNotifier`؟** نعم.
**هل تستدعي `notifyListeners()` بعد `_updatePremiumStatus()`؟** نعم، مباشرة.

### 6. ترتيب إنشاء الخدمات وتمريرها إلى `AppRouter`

في `main.dart`:
```dart
authService = AuthService();                          // 1. يُنشأ أولاً
revenueCatService = RevenueCatService();              // 2. يُنشأ ثانياً
try {
  await revenueCatService.initialize();              // 3. يُهيأ (await!)
} catch (e) { ... }

// ... بعد ذلك ...
appRouter = AppRouter(
  reminderRepository: reminderRepository,
  freeTimeRepository: freeTimeRepository,
  categoryStatRepository: categoryStatRepository,
  notificationService: notificationService,
  aiService: aiService,
  settingsRepository: settingsRepository,
  pendingSharedUrl: pendingSharedUrl,
  aiRescheduleError: aiRescheduleError,
  reminderOpenedId: reminderOpenedId,
  authService: authService,                          // 4. يُمرر بعد اكتمال initialize()
  revenueCatService: revenueCatService,              // 5. يُمرر بعد اكتمال initialize()
);
```

**نعم،** `AppRouter` يُنشأ **بعد** اكتمال `revenueCatService.initialize()`. لكن هناك نقطة مهمة:

في `AuthService._internal()`، عند الإنشاء:
```dart
_authStateSubscription = _auth.authStateChanges().listen((user) {
  // ...
  if (user != null) {
    unawaited(_restoreExternalSessions(user));
  }
  notifyListeners();
});
```

إذا كان هناك مستخدم مسجل دخوله بالفعل في Firebase، فإن `authStateChanges()` سيُطلق حدث فوراً (أو بعد فترة وجيزة)، مما يُحدث `notifyListeners()` في `AuthService`. هذا يُحدّث `GoRouter` عبر `refreshListenable`.

**لكن `RevenueCatService.initialize()`** تحتوي على `Purchases.getCustomerInfo()` التي **بدون timeout** وقد تعلق، مما يمنع اكتمال `_initApp()` **قبل** إنشاء `AppRouter`. لكننا استبعدنا هذا الاحتمال في السؤال 0.

**إذا كانت المشكلة في `redirect` بالفعل (ودجت فلاتر ظاهر):** فهذا يعني أن `_initApp()` اكتملت، و`AppRouter` تم إنشاؤه، و`runApp()` تم استدعاؤه. المشكلة إذًا في منطق `redirect` الذي لا يغير المسار من `'/'`.

### 7. طباعة تشخيصية داخل `redirect`

أضف هذه الطباعة:
```dart
redirect: (context, state) {
  debugPrint('[router] status=${authService.status}, isPremium=${revenueCatService.isPremium}, location=${state.matchedLocation}');
  final status = authService.status;
  final isPremium = revenueCatService.isPremium;
  final isOnLogin = state.matchedLocation == '/login';
  final isOnPaywall = state.matchedLocation == '/paywall';

  if (status == AuthStatus.loading) {
    return '/';
  }

  if (status == AuthStatus.unauthenticated) {
    return isOnLogin ? null : '/login';
  }

  if (!isPremium) {
    return isOnPaywall ? null : '/paywall';
  }

  if (isOnLogin || isOnPaywall) {
    return '/reminders';
  }
  return null;
},
```

**القيم المتوقعة التي ستظهر:**
- إذا كان `status` يبقى `AuthStatus.loading` للأبد: المشكلة في `AuthService` (لم يُستدعى `notifyListeners()` بعد التغيير).
- إذا كان `status` يتغير لكن `isPremium` يبقى `false` دائماً: المشكلة في `RevenueCatService` (لم يُستدعى `notifyListeners()` بعد `_updatePremiumStatus()`).
- إذا كان كلاهما يتغير لكن `redirect` لا يُستدعى مرة أخرى: مشكلة في `refreshListenable`.

---

## إذا كانت المشكلة في `_initApp()` (الشاشة الأصلية ظاهرة فقط):

### 8. أضف `debugPrint` مباشرة قبل وبعد العمليات الرئيسية

```dart
Future<void> _initApp() async {
  debugPrint('[init] Starting _initApp');
  
  try {
    debugPrint('[init] Initializing Firebase');
    await Firebase.initializeApp();
    debugPrint('[init] Firebase initialized');
  } catch (e, stackTrace) {
    debugPrint('Firebase initialization failed: $e\n$stackTrace');
    if (initError == null) initError = 'Firebase initialization failed: $e';
  }

  // ... باقي العمليات مع debugPrint قبل وبعد كل واحدة

  debugPrint('[init] _initApp completed successfully');
}
```

**ما آخر سطر طباعة يظهر؟** هذا سيحدد بالضبط أي عملية توقفت عندها.

### 9. تشغيل `flutter run` وانتظار دقيقتين

قد يظهر `PlatformException` من RevenueCat بعد timeout طويل (غير محدد في الكود).

### 10. قيمة `AppConfig.isSupabaseConfigured`

تحقق من `lib/core/app_config.dart` أو من الـ environment variables:
```dart
// في lib/core/app_config.dart
static bool get isSupabaseConfigured =>
    supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
```

---

## الاستنتاج

إذا كان **ودجت فلاتر `SplashScreen` يظهر** (أيقونة + نص + سبينر صغير)، فإن المشكلة **بالتأكيد في منطق `redirect`**، والأسئلة 1-7 هي التي تحسم السبب.

**السبب الأكثر احتمالاً في `redirect`:**
- `status` يبقى `AuthStatus.loading` (لم يُستدعى `notifyListeners()` في `AuthService` بعد التغيير).
- أو `isPremium` يبقى `false` (لم يُستدعى `notifyListeners()` في `RevenueCatService` بعد `_updatePremiumStatus()`).

**الحل السريع للتشخيص:** أضف `debugPrint` داخل `redirect` كما في السؤال 7، وسيُظهر القيم الفعلية مباشرة.
