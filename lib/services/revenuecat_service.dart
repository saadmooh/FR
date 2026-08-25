import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../core/constants.dart';
import '../core/ui_messenger.dart';

class RevenueCatService extends ChangeNotifier {
  static final RevenueCatService _instance = RevenueCatService._internal();
  factory RevenueCatService() => _instance;
  RevenueCatService._internal();

  static const String _apiKey = 'goog_LfeTyBNEEqcHhnhRvnlRlzIvwbu';

  Offerings? _offerings;
  CustomerInfo? _customerInfo;
  bool _isPremium = false;

  bool get isPremium => _isPremium;
  Offerings? get offerings => _offerings;

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
      _customerInfo = await Purchases.getCustomerInfo();
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
    notifyListeners();
  }

  Future<void> fetchOfferings() async {
    try {
      _offerings = await Purchases.getOfferings();
      if (_offerings?.current != null) {
        debugPrint('Offering: ${_offerings!.current!.identifier}');
        debugPrint('Packages: ${_offerings!.current!.availablePackages.length}');
      }
    } catch (e) {
      debugPrint('Failed to fetch offerings: $e');
    }
  }

  Future<CustomerInfo?> purchasePackage(Package package) async {
    try {
      debugPrint('Purchasing package: ${package.identifier}');
      final result = await Purchases.purchase(PurchaseParams.package(package));
      _customerInfo = result.customerInfo;
      debugPrint(
        'Purchase response - App User ID: ${await Purchases.appUserID}',
      );
      showUiLog('RC Purchase OK | User: ${await Purchases.appUserID}');
      _updatePremiumStatus();
      return _customerInfo;
    } catch (e) {
      debugPrint('Purchase error: $e');
      showUiLog('RC Purchase FAILED: $e', duration: const Duration(seconds: 8));
      rethrow;
    }
  }

  Future<void> linkToUser(String firebaseUid) async {
    try {
      if (!await Purchases.isAnonymous) {
        debugPrint(
          'RevenueCat already linked. App User ID: ${await Purchases.appUserID}',
        );
        showUiLog('RC Already linked: ${await Purchases.appUserID}');
        return;
      }
      final result = await Purchases.logIn(firebaseUid);
      debugPrint('RevenueCat logIn success. Created: ${result.created}');
      debugPrint('App User ID after logIn: ${await Purchases.appUserID}');
      showUiLog(
        'RC logIn OK (created: ${result.created})\n'
        'User: ${await Purchases.appUserID}',
        duration: const Duration(seconds: 6),
      );

      _customerInfo = result.customerInfo;
      _updatePremiumStatus();

      // Recover purchases previously made under a lost anonymous identity
      // (same Google Play account) and attach them to the real user.
      if (!_isPremium) {
        await restoreAfterLogin();
      }
    } catch (e) {
      debugPrint('RevenueCat logIn failed: $e');
      showUiLog('RC logIn FAILED: $e');
    }
  }

  Future<void> restoreAfterLogin() async {
    try {
      final restored = await Purchases.restorePurchases();
      debugPrint('Restored entitlements: ${restored.entitlements.active}');
      showUiLog(
        'RC Restored: ${restored.entitlements.active.keys.toList()}',
      );
      _customerInfo = restored;
      _updatePremiumStatus();
    } catch (e) {
      debugPrint('Restore failed: $e');
    }
  }

  Future<bool> restorePurchases() async {
    try {
      _customerInfo = await Purchases.restorePurchases();
      _updatePremiumStatus();
      return true;
    } catch (e) {
      debugPrint('Restore failed: $e');
      return false;
    }
  }

  Future<void> logout() async {
    try {
      if (await Purchases.isAnonymous) {
        debugPrint('RevenueCat logout skipped: user is anonymous');
        return;
      }
      await Purchases.logOut();
      _customerInfo = null;
      _isPremium = false;
      debugPrint('RevenueCat logged out');
    } catch (e) {
      debugPrint('Logout failed: $e');
    }
  }
}