# RevenueCat Plans Configuration

## API Key Note
The key `goog_LfeTyBNEEqcHhnhRvnlRlzIvwbu` is a **Google Play Public Key** (used for client-side SDK configuration), not a RevenueCat Secret API Key.

To fetch offerings via RevenueCat REST API, you need a **Secret API Key** from:
**RevenueCat Dashboard → Project Settings → API Keys → Secret API Key** (starts with `sk_` or `v1_`)

---

## Current App Configuration

**RevenueCat SDK Key**: `goog_LfeTyBNEEqcHhnhRvnlRlzIvwbu` (Google Play)
**Entitlement ID**: `pro` (defined in `AppConstants.premiumEntitlementId`)

---

## Fetching Plans via RevenueCat REST API

### Endpoint
```
GET https://api.revenuecat.com/v1/offerings
```

### Headers
```
Authorization: Bearer YOUR_SECRET_API_KEY
Content-Type: application/json
```

### Example Response Structure
```json
{
  "offerings": {
    "default": {
      "identifier": "default",
      "description": "Default offering",
      "packages": [
        {
          "identifier": "$rc_monthly",
          "packageType": "MONTHLY",
          "storeProduct": {
            "productIdentifier": "com.yourapp.monthly",
            "title": "Monthly Premium",
            "description": "Unlock all premium features",
            "price": 4.99,
            "priceString": "$4.99",
            "currencyCode": "USD",
            "subscriptionPeriod": "P1M",
            "subscriptionPeriodUnit": "MONTH",
            "subscriptionPeriodNumberOfUnits": 1
          }
        },
        {
          "identifier": "$rc_annual",
          "packageType": "ANNUAL",
          "storeProduct": {
            "productIdentifier": "com.yourapp.annual",
            "title": "Annual Premium",
            "description": "Unlock all premium features - Save 50%",
            "price": 29.99,
            "priceString": "$29.99",
            "currencyCode": "USD",
            "subscriptionPeriod": "P1Y",
            "subscriptionPeriodUnit": "YEAR",
            "subscriptionPeriodNumberOfUnits": 1
          }
        }
      ]
    }
  }
}
```

---

## Plan Display in App

The paywall screen (`lib/screens/paywall_screen.dart`) displays:
- **Title**: `package.storeProduct.title`
- **Description**: `package.storeProduct.description`
- **Price**: `package.storeProduct.priceString`
- **Period**: Derived from `subscriptionPeriod`
- **"POPULAR" badge**: Shown for `PackageType.monthly`

---

## How to Update Plans

1. **RevenueCat Dashboard** → **Offerings** → **Create/Edit Offering**
2. Add **Packages** (Monthly, Annual, etc.)
3. Link to **App Store Connect** / **Google Play Console** products
4. Set **Current Offering** to "default"
5. Plans auto-sync to app via `Purchases.getOfferings()`

---

## Local Testing

Run the app and check debug logs for:
```
Offering: default
Packages: 2
```

Or use the RevenueCat test credentials in the dashboard.