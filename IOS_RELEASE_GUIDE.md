# iOS App Store Release Guide

## ✅ Completed Steps

1. **Bundle Identifier Updated**: Changed from `com.example.bmsproBlack` to `bmspro.black` to match Android
2. **Version Number**: Currently set to `1.0.0+1` in `pubspec.yaml`

## 📋 Next Steps (Requires Xcode & Apple Developer Account)

### Step 1: Register Bundle ID in Apple Developer Portal

1. Go to [Apple Developer Portal](https://developer.apple.com/account)
2. Navigate to **Certificates, Identifiers & Profiles**
3. Click **Identifiers** → **+** (Add)
4. Select **App IDs** → **Continue**
5. Select **App** → **Continue**
6. Fill in:
   - **Description**: BMS Pro Black
   - **Bundle ID**: Select **Explicit** and enter: `bmspro.black`
7. Enable required capabilities:
   - ✅ Push Notifications (if using Firebase Cloud Messaging)
   - ✅ Background Modes (for location services)
   - ✅ Location Services
8. Click **Continue** → **Register**

### Step 2: Create App in App Store Connect

1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Click **My Apps** → **+** → **New App**
3. Fill in:
   - **Platform**: iOS
   - **Name**: BMS Pro Black
   - **Primary Language**: English (or your preferred)
   - **Bundle ID**: Select `bmspro.black` (from Step 1)
   - **SKU**: `bmspro-black-ios` (unique identifier)
   - **User Access**: Full Access (or as needed)
4. Click **Create**

### Step 3: Configure Code Signing in Xcode

1. **Open the project in Xcode**:
   ```bash
   open ios/Runner.xcworkspace
   ```
   ⚠️ **Important**: Open `.xcworkspace`, NOT `.xcodeproj`

2. **Select the Runner project** in the left sidebar

3. **Select the Runner target** (under TARGETS)

4. **Go to "Signing & Capabilities" tab**

5. **Configure signing**:
   - Check ✅ **"Automatically manage signing"**
   - Select your **Team** (your Apple Developer account)
   - Xcode will automatically:
     - Create/update certificates
     - Create provisioning profiles
     - Handle code signing

6. **Verify Bundle Identifier**:
   - Should show: `bmspro.black`
   - If not, update it manually

### Step 4: Prepare App Store Assets

Before building, prepare these assets:

#### Required Screenshots (in PNG or JPEG format):
- **iPhone 6.7" Display** (iPhone 14 Pro Max, 15 Pro Max, etc.)
  - Required sizes: 1290 x 2796 pixels (portrait)
- **iPhone 6.5" Display** (iPhone 11 Pro Max, XS Max, etc.)
  - Required sizes: 1242 x 2688 pixels (portrait)
- **iPad Pro 12.9"** (3rd generation and later)
  - Required sizes: 2048 x 2732 pixels (portrait)

#### Other Required Information:
- **App Description** (up to 4000 characters)
- **Keywords** (up to 100 characters, comma-separated)
- **Support URL** (your website or support page)
- **Marketing URL** (optional)
- **Privacy Policy URL** (REQUIRED - must be a valid URL)
- **App Icon**: 1024 x 1024 pixels (PNG, no transparency)
- **App Category**: Select appropriate categories

### Step 5: Build and Archive the App

#### Option A: Using Xcode (Recommended)

1. **Open Xcode**: `open ios/Runner.xcworkspace`

2. **Select build destination**:
   - Click the device selector (next to Run button)
   - Select **"Any iOS Device"** (not a simulator)

3. **Clean build folder**:
   - Product → Clean Build Folder (Shift + Cmd + K)

4. **Create Archive**:
   - Product → Archive
   - Wait for the build to complete (this may take several minutes)

5. **Verify Archive**:
   - Window → Organizer (or Product → Archive again)
   - You should see your archive listed

#### Option B: Using Flutter CLI (Alternative)

```bash
# Build the iOS app
flutter build ipa --release
```

The IPA file will be at: `build/ios/ipa/bmspro_black.ipa`

**Note**: You'll still need Xcode for code signing configuration.

### Step 6: Upload to App Store Connect

#### If using Xcode Archive:

1. In **Organizer** window, select your archive
2. Click **"Distribute App"**
3. Select **"App Store Connect"** → **Next**
4. Select **"Upload"** → **Next**
5. Review options:
   - ✅ Include bitcode for iOS content (if applicable)
   - ✅ Upload your app's symbols (recommended)
6. Click **Next** → **Upload**
7. Wait for upload to complete

#### If using Flutter CLI IPA:

1. Open **Xcode**
2. Window → **Organizer** → **Archives**
3. Click **"Distribute App"**
4. Select **"App Store Connect"** → **Next**
5. Choose **"Upload"** → **Next**
6. Select your IPA file → **Next**
7. Follow the upload wizard

### Step 7: Complete App Store Listing

1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Select your app **"BMS Pro Black"**
3. Go to the version you just uploaded
4. Fill in all required information:

   **App Information:**
   - App description
   - Keywords
   - Support URL
   - Marketing URL (optional)
   - Privacy Policy URL (REQUIRED)

   **App Store Screenshots:**
   - Upload screenshots for each required device size
   - Add captions if needed

   **App Review Information:**
   - Contact information
   - Demo account (if app requires login)
   - Notes for reviewer

   **Version Information:**
   - What's New in This Version
   - Version number (should match pubspec.yaml)

5. **Save** all changes

### Step 8: Submit for Review

1. In App Store Connect, scroll to **"App Review"** section
2. Answer export compliance questions (if applicable)
3. Review all information
4. Click **"Submit for Review"**
5. Your app status will change to **"Waiting for Review"**

### Step 9: Monitor Review Status

- Check App Store Connect regularly
- Apple typically reviews within 24-48 hours (can take up to 7 days)
- You'll receive email notifications about status changes

## 🔧 Troubleshooting

### Code Signing Issues

If you encounter code signing errors:
1. In Xcode: Runner → Signing & Capabilities
2. Uncheck "Automatically manage signing"
3. Re-check "Automatically manage signing"
4. Select your team again
5. Clean build folder and try again

### Bundle ID Mismatch

If you get bundle ID errors:
- Verify bundle ID in Xcode matches: `bmspro.black`
- Ensure it's registered in Apple Developer Portal
- Check App Store Connect app uses the same bundle ID

### Version Number Issues

To update version:
1. Edit `pubspec.yaml`: `version: 1.0.0+2` (increment build number)
2. Run: `flutter clean && flutter pub get`
3. Rebuild in Xcode

## 📝 Important Notes

- **Keep your Apple Developer credentials safe**
- **Bundle ID cannot be changed after first submission**
- **Version numbers must increment for each release**
- **Privacy Policy URL is mandatory**
- **Screenshots are required before submission**
- **Review process typically takes 1-7 days**

## 🎯 Quick Command Reference

```bash
# Open project in Xcode
open ios/Runner.xcworkspace

# Clean Flutter build
flutter clean

# Get dependencies
flutter pub get

# Build iOS app (creates IPA)
flutter build ipa --release

# Check iOS configuration
flutter doctor -v
```

## ✅ Pre-Submission Checklist

- [ ] Bundle ID registered in Apple Developer Portal
- [ ] App created in App Store Connect
- [ ] Code signing configured in Xcode
- [ ] App builds and archives successfully
- [ ] App uploaded to App Store Connect
- [ ] All screenshots uploaded
- [ ] App description written
- [ ] Keywords added
- [ ] Privacy Policy URL provided
- [ ] Support URL provided
- [ ] App icon uploaded (1024x1024)
- [ ] Version information complete
- [ ] App submitted for review

---

**Need Help?** Check [Apple's App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
