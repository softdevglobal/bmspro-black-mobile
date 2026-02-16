#!/bin/bash

# Script to create a keystore for Android app signing
# Run this script from the android directory

echo "Creating keystore for Android app signing..."
echo ""

# Prompt for keystore location
KEYSTORE_PATH="${1:-../upload-keystore.jks}"

# Run keytool command
keytool -genkey -v -keystore "$KEYSTORE_PATH" \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -alias upload

echo ""
echo "Keystore created at: $KEYSTORE_PATH"
echo ""
echo "IMPORTANT:"
echo "1. Remember your keystore password and key alias password"
echo "2. Update android/key.properties with your passwords"
echo "3. Keep your keystore file safe - you'll need it for all future updates"
echo "4. If you lose the keystore, you won't be able to update your app on Play Store"
