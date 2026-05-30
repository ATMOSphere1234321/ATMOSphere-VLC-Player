#!/usr/bin/env bash
# build-atmosphere-vlc-player.sh — build the ATMOSphere-VLC-Player APK from
# source (libvlcjni compiled via NDK r21e) and copy it into the parent
# ATMOSphere prebuilt-apps tree.
#
# Usage:
#     bash device/rockchip/atmosphere/vlc-player/build-atmosphere-vlc-player.sh
#
# Output:
#     device/rockchip/rk3588/prebuilt_apps/vlc.apk
#     (LOCAL_MODULE := atmosphere.videolan.vlc in prebuilt_apps/Android.mk)
#
# ────────────────────────────────────────────────────────────────────────
# WHY THIS SCRIPT EXISTS (§C1 — VLC audio "loading" state, no sound)
# ────────────────────────────────────────────────────────────────────────
# The VLC audio fix lives in this submodule's source (libvlcjni / app),
# but it only reaches the shipped APK when the APK is REBUILT from that
# source. Unlike lampa/mpv (which ship committed jniLibs/ and need only a
# pure-gradle assemble), VLC's libvlcjni native layer MUST be compiled by
# the NDK — and VLC major-version 3 (this fork is VLC-Android 3.7.x) pins
# its toolchain to NDK r21e (revision 21.4.7075529) in build.gradle:
#
#     toolchainNdkVersion = ... (vlcMajorVersion == 3 ? '21.4.7075529' : ...)
#
# That NDK is fetched by the parent's scripts/setup_ndk_r21.sh into
# tools/build-deps/android-ndk-r21e/. This helper bridges the two: it
# locates the NDK r21e, locates the Android SDK, and drives the VLC
# buildsystem (buildsystem/compile.sh -a arm64 --release) which compiles
# libvlcjni then assembles + signs the universal APK. The result is the
# AUDIO-FIXED, source-current vlc.apk — NOT a stale prebuilt blob.
#
# Signing: VLC's buildsystem signs the release APK using the standard
# Android debug keystore (gradle.properties keyStoreFile defaults to
# $HOME/.android/debug.keystore — see buildsystem/compile.sh). AOSP then
# strips that signature and re-signs with the platform key at image-
# assembly time via LOCAL_REPLACE_PREBUILT_APK_INSTALLED in
# prebuilt_apps/Android.mk.
#
# Skippable via SKIP_VLC=1 for hosts without NDK r21e fetched (the parent
# step_build_vlc treats a missing NDK as a non-fatal skip so the existing
# prebuilt vlc.apk is used — same pattern as SKIP_LAMPA / SKIP_MPV).
#
# Fails loudly so scripts/build.sh halts early on real errors.
# ────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

cd "$SCRIPT_DIR"

echo "[ATMOSphere-VLC] build-atmosphere-vlc-player.sh"
echo "  script dir: $SCRIPT_DIR"
echo "  parent:     $PARENT_ROOT"

# ── 1. Locate NDK r21e (the §C1 unblock dependency) ──────────────────────
# Order: explicit ANDROID_NDK / ANDROID_NDK_HOME env (operator override) →
# the canonical setup_ndk_r21.sh install path under tools/build-deps/.
_NDK=""
for cand in \
    "${ANDROID_NDK:-}" \
    "${ANDROID_NDK_HOME:-}" \
    "$PARENT_ROOT/tools/build-deps/android-ndk-r21e"; do
    if [ -n "$cand" ] && [ -f "$cand/source.properties" ]; then
        _NDK="$cand"
        break
    fi
done

if [ -z "$_NDK" ]; then
    echo "[ATMOSphere-VLC] NDK r21e not found."
    echo "[ATMOSphere-VLC]   Expected at: $PARENT_ROOT/tools/build-deps/android-ndk-r21e"
    echo "[ATMOSphere-VLC]   Fetch it with: bash scripts/setup_ndk_r21.sh"
    echo "[ATMOSphere-VLC]   (exit 3 — parent step_build_vlc treats this as a non-fatal skip)"
    exit 3
fi

# Verify the revision matches VLC v3's pinned toolchain (21.4.7075529).
_NDK_REV="$(grep -o '^Pkg.Revision.*' "$_NDK/source.properties" 2>/dev/null | cut -d= -f2 | tr -d ' ' || true)"
echo "[ATMOSphere-VLC] NDK: $_NDK (revision ${_NDK_REV:-unknown})"
case "$_NDK_REV" in
    21.4.*) : ;;  # r21e — correct toolchain for VLC v3
    *)
        echo "[ATMOSphere-VLC] WARNING: NDK revision ${_NDK_REV:-unknown} is not r21.4.x."
        echo "[ATMOSphere-VLC]   VLC-Android v3 build.gradle pins toolchainNdkVersion=21.4.7075529."
        echo "[ATMOSphere-VLC]   Proceeding, but the libvlcjni compile may fail."
        ;;
esac
export ANDROID_NDK="$_NDK"

# ── 2. Locate Android SDK ────────────────────────────────────────────────
_SDK="${ANDROID_SDK:-${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}}"
if [ ! -d "$_SDK/platforms" ] && [ ! -d "$_SDK/platform-tools" ]; then
    echo "[ATMOSphere-VLC] ERROR: Android SDK not found at: $_SDK"
    echo "[ATMOSphere-VLC]   Set ANDROID_HOME / ANDROID_SDK_ROOT to your SDK directory."
    exit 2
fi
export ANDROID_SDK="$_SDK"
export ANDROID_HOME="$_SDK"
echo "[ATMOSphere-VLC] SDK: $ANDROID_SDK"

# ── 3. JDK pick (gradle 8.x + AGP 8.13.2 require Java 17 or 21) ───────────
_pick_jdk() {
    for cand in \
        "$PARENT_ROOT/prebuilts/jdk/jdk21/linux-x86" \
        "$PARENT_ROOT/prebuilts/jdk/jdk21" \
        /usr/lib/jvm/java-21-openjdk \
        /usr/lib/jvm/java-21-openjdk-amd64 \
        /usr/lib/jvm/java-21-openjdk-*.x86_64 \
        "$PARENT_ROOT/prebuilts/jdk/jdk17/linux-x86" \
        "$PARENT_ROOT/prebuilts/jdk/jdk17" \
        /usr/lib/jvm/java-17-openjdk \
        /usr/lib/jvm/java-17-openjdk-amd64 \
        /usr/lib/jvm/java-17-openjdk-*.x86_64; do
        for actual in $cand; do
            if [ -x "$actual/bin/java" ]; then
                export JAVA_HOME="$actual"
                return 0
            fi
        done
    done
    echo "[ATMOSphere-VLC] WARNING: no JDK 17/21 found — gradle may fail on older Java"
    return 1
}
_pick_jdk || true
if [ -n "${JAVA_HOME:-}" ]; then
    echo "[ATMOSphere-VLC] JAVA_HOME=$JAVA_HOME"
    "$JAVA_HOME/bin/java" -version 2>&1 | head -1
fi

# ── 4. Ensure a debug keystore exists (VLC buildsystem signs release with it) ─
_DEBUG_KS="$HOME/.android/debug.keystore"
if [ ! -f "$_DEBUG_KS" ]; then
    echo "[ATMOSphere-VLC] creating $_DEBUG_KS (fresh machine; standard debug passwords)"
    mkdir -p "$HOME/.android"
    keytool -genkey -v \
        -keystore "$_DEBUG_KS" \
        -storepass android -keypass android \
        -alias androiddebugkey \
        -dname "CN=Android Debug,O=Android,C=US" \
        -keyalg RSA -keysize 2048 -validity 10000 2>&1 | tail -2
fi

# ── 5. Build: compile libvlcjni (NDK) + assemble + sign the universal APK ─
# `-a arm64` selects arm64-v8a (the buildsystem assembles a universal APK
# carrying both arm64-v8a + armeabi-v7a — matches the shipped vlc.apk and
# the APK_LIB_MAP arm64 libvlcjni.so entry in scripts/build.sh).
# `--release` selects the Release buildtype + signs with the keystore.
echo "[ATMOSphere-VLC] running: buildsystem/compile.sh -a arm64 --release"
echo "[ATMOSphere-VLC]   (compiles libvlcjni via NDK r21e then assembles the APK)"
bash buildsystem/compile.sh -a arm64 --release

# ── 6. Locate the signed release APK ─────────────────────────────────────
# VLC's gradle lands the universal release APK under
# application/app/build/outputs/apk/release/. Prefer the signed artifact.
_OUT_DIR="application/app/build/outputs/apk/release"
APK_PATH=""
for pat in \
    "$_OUT_DIR/VLC-Android-signed.apk" \
    "$_OUT_DIR/VLC-Android-*-all.apk" \
    "$_OUT_DIR/*-all.apk" \
    "$_OUT_DIR/*.apk"; do
    for f in $pat; do
        if [ -f "$f" ]; then
            APK_PATH="$f"
            break
        fi
    done
    [ -n "$APK_PATH" ] && break
done

if [ -z "$APK_PATH" ] || [ ! -f "$APK_PATH" ]; then
    echo "[ATMOSphere-VLC] ERROR: compile.sh reported success but no APK found under $_OUT_DIR/"
    ls -la "$_OUT_DIR/" 2>&1 | head -10
    exit 2
fi
echo "[ATMOSphere-VLC] built APK: $APK_PATH"

# ── 7. Copy into the parent prebuilt-apps tree ───────────────────────────
DEST="$PARENT_ROOT/device/rockchip/rk3588/prebuilt_apps/vlc.apk"
cp -f "$APK_PATH" "$DEST"
echo "[ATMOSphere-VLC] copied to: $DEST"
ls -lh "$DEST"

echo "[ATMOSphere-VLC] done. scripts/build.sh will pick this APK up via"
echo "  device/rockchip/rk3588/prebuilt_apps/Android.mk (LOCAL_MODULE :="
echo "  atmosphere.videolan.vlc) and re-sign with the platform key at"
echo "  system-image assembly. APK_LIB_MAP extracts libvlcjni.so for"
echo "  debugfs injection."
