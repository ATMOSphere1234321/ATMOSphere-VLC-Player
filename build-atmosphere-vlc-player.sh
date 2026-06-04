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

# ── 1. Locate the NDK ────────────────────────────────────────────────────
# §C3 build-fix (ATMOSphere): the shipped vlc.apk carries lib/arm64-v8a/
# libvlcjni.so and the parent APK_LIB_MAP extracts the arm64 libvlcjni.so
# (scripts/build.sh: `atmosphere.videolan.vlc:app:arm64:libvlcjni.so`), so the
# native build target is arm64-v8a. VLC v3's libvlcjni/buildsystem/
# compile-libvlc.sh HARD-REQUIRES NDK r27 or r28 for the 64-bit (arm64) build
# (`NDK v27-28 needed for 64-bit, got NN` → exit 1) — r21e only builds the
# 32-bit (armeabi-v7a) target. compile.sh derives android.ndkFullVersion from
# $ANDROID_NDK into local.properties, and the fork's build.gradle reads
# `properties.getProperty('android.ndkFullVersion')` FIRST in its
# toolchainNdkVersion expression, so feeding an r28 here keeps the native
# compile AND the gradle assemble step on the SAME toolchain (no split).
#
# Resolution order: explicit ANDROID_NDK / ANDROID_NDK_HOME env (operator
# override, highest priority) → an r27/r28 found under the Android SDK's
# ndk/ directory → the legacy tools/build-deps/android-ndk-r21e (last resort;
# only valid for a 32-bit `-a arm` build).
_sdk_root="${ANDROID_SDK:-${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}}"
_ndk_rev_of() { grep -o '^Pkg.Revision.*' "$1/source.properties" 2>/dev/null | cut -d= -f2 | tr -d ' '; }

_NDK=""
# (a) explicit operator override
for cand in "${ANDROID_NDK:-}" "${ANDROID_NDK_HOME:-}"; do
    if [ -n "$cand" ] && [ -f "$cand/source.properties" ]; then _NDK="$cand"; break; fi
done
# (b) autodiscover an r27/r28 under the SDK (VLC v3 arm64 requirement)
if [ -z "$_NDK" ] && [ -d "$_sdk_root/ndk" ]; then
    for cand in "$_sdk_root"/ndk/28.* "$_sdk_root"/ndk/27.*; do
        [ -f "$cand/source.properties" ] || continue
        case "$(_ndk_rev_of "$cand")" in 27.*|28.*) _NDK="$cand"; break ;; esac
    done
fi
# (c) legacy r21e (only usable for the 32-bit target)
if [ -z "$_NDK" ] && [ -f "$PARENT_ROOT/tools/build-deps/android-ndk-r21e/source.properties" ]; then
    _NDK="$PARENT_ROOT/tools/build-deps/android-ndk-r21e"
fi

if [ -z "$_NDK" ]; then
    echo "[ATMOSphere-VLC] NDK not found (need r27/r28 for the arm64 build)."
    echo "[ATMOSphere-VLC]   Install via Android SDK Manager: sdkmanager 'ndk;28.2.13676358'"
    echo "[ATMOSphere-VLC]   or set ANDROID_NDK to an r27/r28 install."
    echo "[ATMOSphere-VLC]   (exit 3 — parent step_build_vlc treats this as a non-fatal skip)"
    exit 3
fi

_NDK_REV="$(_ndk_rev_of "$_NDK")"
echo "[ATMOSphere-VLC] NDK: $_NDK (revision ${_NDK_REV:-unknown})"
case "$_NDK_REV" in
    27.*|28.*) : ;;  # r27/r28 — required by VLC v3 compile-libvlc.sh for arm64
    *)
        echo "[ATMOSphere-VLC] WARNING: NDK revision ${_NDK_REV:-unknown} is not r27/r28."
        echo "[ATMOSphere-VLC]   VLC v3 compile-libvlc.sh requires NDK r27/r28 for the 64-bit"
        echo "[ATMOSphere-VLC]   (arm64) target and will exit 1 otherwise. Proceeding anyway"
        echo "[ATMOSphere-VLC]   (correct only if you switch compile.sh to a 32-bit '-a arm' build)."
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

# §C3 build-fix (ATMOSphere): the fork's app/build.gradle `signingConfigs.release`
# is GATED on `project.hasProperty('keyStoreFile')` — it stays inactive (→ an
# UNSIGNED APK) unless keyStoreFile / storealias / storepwd gradle properties
# are supplied. The prebuilt is declared `LOCAL_CERTIFICATE := PRESIGNED` in
# device/rockchip/rk3588/prebuilt_apps/Android.mk (AOSP does NOT re-sign it), so
# an unsigned vlc.apk would be rejected by PackageManager at install. Feed the
# debug keystore as ORG_GRADLE_PROJECT_* env vars (gradle reads these as project
# properties) so the `signedRelease` build type below produces a signed APK.
# (Debug-signed is correct for a /system PRESIGNED prebuilt — same as the prior
# shipped vlc.apk.)
export ORG_GRADLE_PROJECT_keyStoreFile="$_DEBUG_KS"
export ORG_GRADLE_PROJECT_storealias="androiddebugkey"
export ORG_GRADLE_PROJECT_storepwd="android"

# ── 5. Build: compile libvlcjni (NDK) + assemble + sign the universal APK ─
# `-a arm64` selects arm64-v8a (the buildsystem assembles a universal APK
# carrying both arm64-v8a + armeabi-v7a — matches the shipped vlc.apk and
# the APK_LIB_MAP arm64 libvlcjni.so entry in scripts/build.sh).
# `--release` selects the Release buildtype + signs with the keystore.
# §C3 build-fix (ATMOSphere): VLC's contrib build (soxr, and any other
# contrib whose CMakeLists declares `cmake_minimum_required(VERSION <3.5)`)
# fails to configure under modern host CMake (>=4.0 removed compatibility
# with `cmake_minimum_required` < 3.5), aborting the whole contrib `make`:
#   CMake Error at CMakeLists.txt:4 (cmake_minimum_required):
#     Compatibility with CMake < 3.5 has been removed from CMake.
#     Or, add -DCMAKE_POLICY_VERSION_MINIMUM=3.5 to try configuring anyway.
#   make: *** [../src/soxr/rules.mak:42: .soxr] Error 1
# The VLC contrib CMAKE macro (vlc/contrib/src/main.mak) hardcodes its -D
# flags with no extra-flags hook, and that file is part of the FETCHED VLC
# source (regenerated by get-vlc.sh every clean build), so patching it would
# not persist. CMake honors the CMAKE_POLICY_VERSION_MINIMUM *environment*
# variable identically to the -D flag, so exporting it here makes every
# contrib cmake invocation accept the ancient minimum. Scoped to this build
# only (it is a child-process env, not a persistent setting).
export CMAKE_POLICY_VERSION_MINIMUM="${CMAKE_POLICY_VERSION_MINIMUM:-3.5}"
echo "[ATMOSphere-VLC] CMAKE_POLICY_VERSION_MINIMUM=$CMAKE_POLICY_VERSION_MINIMUM (§C3 — host CMake >=4.0 contrib-compat)"

# §C3 build-fix (ATMOSphere): some autotools-based contribs that cross-compile
# but also build native build-time helper tools (gettext builds msgfmt/msgmerge
# for the BUILD machine) require a NATIVE compiler for the build host. VLC's
# contrib config.mak sets CC to the NDK *cross* clang globally, and gettext's
# configure then fails:
#   configure: WARNING: using cross tools not prefixed with host triplet
#   configure: error: Cannot find native C99 compiler: please define BUILDCC.
# Point BUILDCC (+ the conventional native build vars) at the host toolchain so
# the build-machine helper programs compile with /usr/bin/cc. These are only
# consumed by configure scripts that distinguish build-vs-host compilers; the
# cross targets keep using the NDK clang from config.mak.
_host_cc="$(command -v cc || command -v gcc || command -v clang || true)"
_host_cxx="$(command -v c++ || command -v g++ || command -v clang++ || true)"
if [ -n "$_host_cc" ]; then
    export BUILDCC="${BUILDCC:-$_host_cc}"
    export BUILD_CC="${BUILD_CC:-$_host_cc}"
    export CC_FOR_BUILD="${CC_FOR_BUILD:-$_host_cc}"
    [ -n "$_host_cxx" ] && export CXX_FOR_BUILD="${CXX_FOR_BUILD:-$_host_cxx}"
    echo "[ATMOSphere-VLC] BUILDCC=$BUILDCC (§C3 — native build-host compiler for gettext et al.)"
fi

# §C3 build-fix (ATMOSphere): use --signrelease (NOT --release). compile.sh maps
# --release → BUILDTYPE=Release → assembleRelease (UNSIGNED per-ABI splits, no
# universal), whereas --signrelease → BUILDTYPE=signedRelease → assembleSignedRelease
# → the SIGNED universal `VLC-Android-signed.apk` (which step 6 below prefers
# first). Required because the prebuilt is PRESIGNED (AOSP does not re-sign).
echo "[ATMOSphere-VLC] running: buildsystem/compile.sh -a arm64 --signrelease"
echo "[ATMOSphere-VLC]   (compiles libvlcjni via NDK r27/r28 then assembles + signs the universal APK)"
bash buildsystem/compile.sh -a arm64 --signrelease

# ── 6. Locate the SIGNED release APK ─────────────────────────────────────
# §C3 build-fix (ATMOSphere): `--signrelease` lands its output under the
# `signedRelease/` build-type dir (NOT `release/`, which holds the UNSIGNED
# `assembleRelease` artifacts from any prior plain-release run). The earlier
# step-6 glob only searched `release/`, so it picked the stale UNSIGNED arm64
# split — fatal for a PRESIGNED prebuilt. Search signedRelease/ FIRST; prefer
# the universal `VLC-Android-signed.apk`, else the arm64-v8a split (matches the
# APK_LIB_MAP `atmosphere.videolan.vlc:app:arm64:libvlcjni.so` entry — the only
# ABI injected into the system image). The `release/` dir remains a last-resort
# fallback for legacy builds, but step 6b below REJECTS an unsigned result.
_SIGNED_DIR="application/app/build/outputs/apk/signedRelease"
_REL_DIR="application/app/build/outputs/apk/release"
APK_PATH=""
for pat in \
    "$_SIGNED_DIR/VLC-Android-signed.apk" \
    "$_SIGNED_DIR/VLC-Android-*-all.apk" \
    "$_SIGNED_DIR/VLC-Android-*-arm64-v8a.apk" \
    "$_SIGNED_DIR/*-all.apk" \
    "$_SIGNED_DIR/*-arm64-v8a.apk" \
    "$_SIGNED_DIR/*.apk" \
    "$_REL_DIR/VLC-Android-signed.apk" \
    "$_REL_DIR/VLC-Android-*-all.apk" \
    "$_REL_DIR/VLC-Android-*-arm64-v8a.apk" \
    "$_REL_DIR/*.apk"; do
    for f in $pat; do
        if [ -f "$f" ]; then
            APK_PATH="$f"
            break
        fi
    done
    [ -n "$APK_PATH" ] && break
done

if [ -z "$APK_PATH" ] || [ ! -f "$APK_PATH" ]; then
    echo "[ATMOSphere-VLC] ERROR: compile.sh reported success but no APK found under"
    echo "[ATMOSphere-VLC]   $_SIGNED_DIR/ or $_REL_DIR/"
    ls -la "$_SIGNED_DIR/" "$_REL_DIR/" 2>&1 | head -16
    exit 2
fi
echo "[ATMOSphere-VLC] built APK: $APK_PATH"

# ── 6b. Verify the chosen APK is SIGNED (PRESIGNED prebuilt requirement) ──
# The prebuilt is `LOCAL_CERTIFICATE := PRESIGNED` — AOSP ships its signature
# as-is, so an unsigned APK would be rejected by PackageManager at install.
# Refuse to copy an unsigned APK rather than ship a broken prebuilt.
_apksigner=""
for c in "${ANDROID_SDK}"/build-tools/*/apksigner; do [ -x "$c" ] && _apksigner="$c"; done
if [ -n "$_apksigner" ]; then
    if "$_apksigner" verify "$APK_PATH" >/dev/null 2>&1; then
        echo "[ATMOSphere-VLC] APK signature: VERIFIED ($_apksigner)"
    else
        echo "[ATMOSphere-VLC] ERROR: chosen APK is UNSIGNED — refusing to ship a PRESIGNED prebuilt unsigned."
        echo "[ATMOSphere-VLC]   APK: $APK_PATH"
        echo "[ATMOSphere-VLC]   The signedRelease signingConfig requires keyStoreFile/storealias/storepwd"
        echo "[ATMOSphere-VLC]   gradle props (exported as ORG_GRADLE_PROJECT_* above). Check the keystore."
        exit 2
    fi
else
    echo "[ATMOSphere-VLC] WARNING: apksigner not found under $ANDROID_SDK/build-tools — cannot verify signature."
fi

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
