#!/bin/bash

# Quick script to prepare and build iOS app for App Store
# Make sure you've completed Xcode setup first!

echo "🚀 iOS Build Preparation Script"
echo "================================"
echo ""

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter is not installed or not in PATH"
    exit 1
fi

# Check if we're in the right directory
if [ ! -f "pubspec.yaml" ]; then
    echo "❌ Please run this script from the project root directory"
    exit 1
fi

echo "✅ Flutter found"
echo ""

# Clean previous builds
echo "🧹 Cleaning previous builds..."
flutter clean

# Get dependencies
echo "📦 Getting Flutter dependencies..."
flutter pub get

# Install iOS pods
echo "📱 Installing iOS CocoaPods dependencies..."
cd ios
pod install
cd ..

echo ""
echo "✅ Preparation complete!"
echo ""
echo "📋 Next Steps:"
echo "1. Open Xcode: open ios/Runner.xcworkspace"
echo "2. Configure code signing in Xcode (Signing & Capabilities tab)"
echo "3. Select 'Any iOS Device' as build destination"
echo "4. Product → Archive to create the build"
echo "5. Follow the guide in IOS_RELEASE_GUIDE.md"
echo ""
echo "💡 Tip: Make sure you have:"
echo "   - Apple Developer account ($99/year)"
echo "   - Bundle ID registered in Apple Developer Portal"
echo "   - App created in App Store Connect"
echo ""
