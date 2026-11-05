#!/bin/sh
# Exports the Android APK with the Gradle build (notification plugin included).
#   tools/export_android.sh [debug|release] [output.apk]
# Needs: Godot 4.7.2 on PATH, Android Studio's JDK, the Android SDK, the debug
# keystore, and the one-time setup described in CLAUDE.md (build template in
# android/build, NDK 29). Release builds also need the release keystore
# variables (GODOT_ANDROID_KEYSTORE_RELEASE_*) in the environment.
set -eu
cd "$(dirname "$0")/.."
MODE="${1:-debug}"
OUT="${2:-build/HuntingGame-gradle.apk}"

export JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="${GODOT_ANDROID_KEYSTORE_DEBUG_PATH:-$HOME/.android/debug.keystore}"
export GODOT_ANDROID_KEYSTORE_DEBUG_USER="${GODOT_ANDROID_KEYSTORE_DEBUG_USER:-androiddebugkey}"
export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD="${GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD:-android}"

mkdir -p "$(dirname "$OUT")"
godot --headless --path . "--export-$MODE" "Android" "$OUT" 2>&1 | grep -vE '^\s*$|ADDING:' | tail -12
ls -la "$OUT"
