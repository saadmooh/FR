import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

class RevenueCatService {
  static final RevenueCatService _instance = RevenueCatService._internal();
  factory RevenueCatService() => _instance;
  RevenueCatService._internal();

  static const String _apiKey = 'goog_WnLgVtBcHCJndRicBHtliPtJENT';
  static const String _premiumEntitlement = 'premium';

  Offerings? _offerings;
  CustomerInfo? _customerInfo;
  bool _isPremium = false;

  bool get isPremium => _isPremium;
  Offerings? get offerings => _offerings;

  Future<void> initialize() async {
    await Purchases.setLogLevel(LogLevel.debug);
    await Purchases.configure(PurchasesConfiguration(_apiKey));

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
    _isPremium = entitlements?.active[_premiumEntitlement]?.isActive ?? false;
    debugPrint('Premium status: $_isPremium');
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

  Future<bool> purchasePackage(Package package) async {
    try {
      debugPrint('Purchasing package: ${package.identifier}');
       _customerInfo = (await Purchases.purchasePackage(package)).customerInfo;
      _updatePremiumStatus();
      return _isPremium;
    } catch (e) {
      debugPrint('Purchase error: $e');
      return false;
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
      await Purchases.logOut();
      _isPremium = false;
    } catch (e) {
      debugPrint('Logout failed: $e');
    }
  }
}