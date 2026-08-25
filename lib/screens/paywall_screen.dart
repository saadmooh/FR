import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../core/app_theme.dart';
import '../core/constants.dart';
import '../core/translations.dart';
import '../core/locale_manager.dart';
import '../services/revenuecat_service.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  bool _isLoading = false;
  bool _isLoadingOfferings = true;
  Package? _selectedPackage;
  List<Package> _packages = [];

  String get _locale => LocaleManager.instance.getLocale();

  @override
  void initState() {
    super.initState();
    _loadOfferings();
  }

  Future<void> _loadOfferings() async {
    setState(() => _isLoadingOfferings = true);
    try {
      final offerings = await Purchases.getOfferings();
      if (offerings.current != null) {
        setState(() {
          _packages = offerings.current!.availablePackages;
          if (_packages.isNotEmpty) {
            final monthly = _packages.firstWhere(
              (p) => p.packageType == PackageType.monthly,
              orElse: () => _packages.first,
            );
            _selectedPackage = monthly;
          }
        });
      }
    } catch (e) {
      debugPrint('Failed to load offerings: $e');
    }
    setState(() => _isLoadingOfferings = false);
  }

  Future<void> _purchase() async {
    if (_selectedPackage == null) return;

    setState(() => _isLoading = true);

    try {
      final customerInfo =
          await RevenueCatService().purchasePackage(_selectedPackage!);
      if (!mounted) return;

      final isPremium = customerInfo?.entitlements.active
              .containsKey(AppConstants.premiumEntitlementId) ??
          false;

      if (isPremium) {
        _showSuccessAndClose();
      } else {
        // Purchase went through but no active entitlement in the response —
        // try restoring before reporting failure (no silent ignore).
        await RevenueCatService().restoreAfterLogin();
        if (!mounted) return;
        if (RevenueCatService().isPremium) {
          _showSuccessAndClose();
        } else {
          _showError(Translations.purchaseFailed(_locale));
        }
      }
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      debugPrint('Purchase error ($code): $e');
      if (mounted && code != PurchasesErrorCode.purchaseCancelledError) {
        _showError(Translations.purchaseFailed(_locale));
      }
    } catch (e) {
      debugPrint('Purchase error: $e');
      if (mounted) {
        _showError(Translations.purchaseFailed(_locale));
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  void _showSuccessAndClose() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(Translations.premiumActivated(_locale)),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
    );
    context.go('/');
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
    );
  }

  Future<void> _restore() async {
    setState(() => _isLoading = true);
    try {
      final customerInfo = await Purchases.restorePurchases();
      final isPremium = customerInfo.entitlements.active
          .containsKey(AppConstants.premiumEntitlementId);

      if (isPremium && mounted) {
        _showSuccessAndClose();
      }
    } catch (e) {
      debugPrint('Restore error: $e');
    }
    setState(() => _isLoading = false);
  }

  List<String> _getPremiumFeatures() {
    return [
      Translations.premiumFeatureUnlimited(_locale),
      Translations.premiumFeatureCloudSync(_locale),
      Translations.premiumFeaturePriorityAI(_locale),
      Translations.premiumFeatureExcelExport(_locale),
      Translations.premiumFeatureAdvancedStats(_locale),
      Translations.premiumFeatureNoAds(_locale),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.whiteBackground,
      appBar: AppBar(
        backgroundColor: AppColors.whiteSurface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.whiteTextPrimary),
          onPressed: () => context.go('/'),
        ),
        title: Text(
          Translations.upgradeToPremium(_locale),
          style: Theme.of(context).appBarTheme.titleTextStyle,
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withAlpha(25),
                      borderRadius: BorderRadius.zero,
                    ),
                    child: const Icon(
                      Icons.workspace_premium,
                      size: 40,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    Translations.premiumTitle(_locale),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: AppColors.whiteTextPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    Translations.premiumSubtitle(_locale),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.whiteTextSecondary,
                          fontSize: 14,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  ...List.generate(_getPremiumFeatures().length, (i) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: AppColors.accent,
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _getPremiumFeatures()[i],
                              style: TextStyle(
                                color: AppColors.whiteTextPrimary,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 24),
                  if (_isLoadingOfferings)
                    const Center(child: CircularProgressIndicator())
                  else if (_packages.isEmpty)
                    Text(
                      Translations.noPackagesAvailable(_locale),
                      style: TextStyle(color: AppColors.whiteTextSecondary),
                    )
                  else
                    _buildPackageSelector(),
                ],
              ),
            ),
          ),
          _buildBottomSection(),
        ],
      ),
    );
  }

  Widget _buildPackageSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          Translations.choosePlan(_locale),
          style: TextStyle(
            color: AppColors.whiteTextPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        ..._packages.map((pkg) => _buildPackageTile(pkg)),
      ],
    );
  }

  Widget _buildPackageTile(Package package) {
    final isSelected = _selectedPackage == package;
    final isMonthly = package.packageType == PackageType.monthly;

    return GestureDetector(
      onTap: () => setState(() => _selectedPackage = package),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.accent.withAlpha(25)
              : AppColors.whiteSurface,
          borderRadius: BorderRadius.zero,
          border: Border.all(
            color: isSelected ? AppColors.whiteAccent : AppColors.whiteBorder,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Radio<bool>(
              value: true,
              groupValue: isSelected,
              onChanged: (_) => setState(() => _selectedPackage = package),
              activeColor: AppColors.whiteAccent,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        package.storeProduct.title,
                        style: TextStyle(
                          color: AppColors.whiteTextPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (isMonthly) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          color: AppColors.whiteAccent,
                          child: Text(
                            Translations.popular(_locale),
                            style: TextStyle(
                              color: AppColors.whiteBackground,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    package.storeProduct.description,
                    style: TextStyle(
                      color: AppColors.whiteTextSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              package.storeProduct.priceString,
              style: TextStyle(
                color: AppColors.whiteTextPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.whiteSurface,
        border: Border(top: BorderSide(color: AppColors.whiteBorder)),
      ),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed:
                  _isLoading || _selectedPackage == null ? null : _purchase,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.whiteAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                disabledBackgroundColor: AppColors.whiteBorder,
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      Translations.subscribeNow(_locale),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _isLoading ? null : _restore,
            child: Text(
              Translations.restorePurchases(_locale),
              style: TextStyle(
                color: AppColors.whiteTextSecondary,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
