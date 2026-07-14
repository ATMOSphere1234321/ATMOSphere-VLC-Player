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
# §C3 build-fix (ATMOSphere) ATM-339: belt-and-suspenders stale-build-dir purge.
# compile-libvlc.sh now reconfigures when its build-android-<tuple>/config.status
# was configured for a different absolute prefix (the canonical case: a host-
# configured build dir reused inside the §12.9 container where the AOSP tree is
# mounted at /aosp, so the host-absolute -I.../contrib/... include paths baked
# into the generated Makefiles point at non-existent dirs → src/extras/libc.c
# fails `call to undeclared function 'iconv_open'`). This helper applies the SAME
# precise condition one layer earlier so a stale host-configured leftover never
# leaks into the build at all. Only a dir whose config.status does NOT reference
# the CURRENT location is wiped — a valid in-place build dir is preserved (no
# needless full reconfigure on repeat host runs).
# Ref: qa-results/host_batch_119/VLC_BUILD_BLOCKER_RCA.md §2.3 / §4.A item 2.
_vlc_src_dir=""
if [ -f "$SCRIPT_DIR/libvlcjni/src/libvlc.h" ]; then
    _vlc_src_dir="$SCRIPT_DIR/libvlcjni"
elif [ -d "$SCRIPT_DIR/libvlcjni/vlc" ]; then
    _vlc_src_dir="$SCRIPT_DIR/libvlcjni/vlc"
fi
if [ -n "$_vlc_src_dir" ]; then
    for _bdir in "$_vlc_src_dir"/build-android-*; do
        [ -d "$_bdir" ] || continue
        _tuple="$(basename "$_bdir" | sed 's/^build-android-//')"
        _expected_prefix="$_vlc_src_dir/contrib/$_tuple"
        if [ -e "$_bdir/config.status" ] && \
           ! grep -q -- "$_expected_prefix" "$_bdir/config.status" 2>/dev/null; then
            echo "[ATMOSphere-VLC] purging stale build dir configured for a different prefix:"
            echo "[ATMOSphere-VLC]   $_bdir (expected '$_expected_prefix' — not found in config.status)"
            rm -rf "$_bdir"
        fi
        # ATM-343 (2026-06-23): mixed host/container config.status detection.
        # The ATM-339 predicate above wipes a build dir whose config.status
        # LACKS the expected prefix; but a config.status reused across the
        # host↔§12.9-container boundary can record BOTH the current prefix AND
        # a *foreign* absolute build-root path (host /run/media/.../contrib +
        # container /aosp/.../contrib). That mixed state still satisfies the
        # ATM-339 "expected prefix present" check yet bakes non-existent
        # -I<foreign>/contrib/... include dirs into the generated Makefiles →
        # live555 'UsageEnvironment.hh not found'. Detect + wipe: any absolute
        # contrib/build-android root token recorded in config.status that is
        # NOT under the current source root ($_expected_root) is a stale
        # foreign build-root path and forces a full reconfigure.
        # Ref: qa-results/host_batch_119/VLC_BUILD_BLOCKER_RCA.md §4.A item 2;
        #      test_atm339_reconfigure_detection.sh CASE6/7/8.
        _expected_root="$_vlc_src_dir"
        if [ -d "$_bdir" ] && [ -e "$_bdir/config.status" ]; then
            _foreign_roots="$(grep -oE '/[A-Za-z0-9._/+-]*/(contrib|build-android)[A-Za-z0-9._/+-]*' "$_bdir/config.status" 2>/dev/null \
                | grep -vE "^${_expected_root}/" | sort -u)"
            if [ -n "$_foreign_roots" ]; then
                echo "[ATMOSphere-VLC] purging build dir with a stale foreign build-root path in config.status:"
                echo "[ATMOSphere-VLC]   $_bdir (foreign roots not under '$_expected_root'):"
                printf '[ATMOSphere-VLC]     %s\n' $_foreign_roots
                rm -rf "$_bdir"
            fi
        fi
    done
fi

# §C3 build-fix (ATMOSphere) ATM-339 (inner-guard, 2026-07-05): idempotent
# RUNTIME PATCH of compile-libvlc.sh's own innermost reconfigure guard
# (libvlcjni/buildsystem/compile-libvlc.sh:612). The outer purge above
# (lines 243-286) only protects the scripts/build.sh -> step_build_vlc() ->
# THIS wrapper -> buildsystem/compile.sh call chain. Two other entry points
# bypass it entirely: buildsystem/compile-medialibrary.sh:45 sources
# compile-libvlc.sh DIRECTLY (`AVLC_SOURCED=1 . libvlcjni/buildsystem/compile-libvlc.sh`),
# and any manual/CI `bash buildsystem/compile.sh` or
# `bash libvlcjni/buildsystem/compile-libvlc.sh` invocation. libvlcjni/ is
# untracked/foreign-origin (VideoLAN upstream, .gitignore'd, reset via
# `git reset --hard $LIBVLCJNI_TESTED_HASH` on every re-init per
# buildsystem/compile.sh:307-339), so a one-time hand-edit of
# compile-libvlc.sh would be silently LOST on any fresh clone / re-init --
# the SAME reasoning this script's own author already applied to
# vlc/contrib/src/main.mak (see CMAKE_POLICY_VERSION_MINIMUM above). This
# step re-applies the SAME prefix-mismatch predicate the purge above already
# computes (VLC_EXPECTED_CONTRIB_PREFIX mirrors _expected_prefix) directly
# INTO compile-libvlc.sh's own guard, on EVERY invocation, guarded by the
# ATM339-INNER-GUARD-PATCH marker for idempotency. Non-fatal by design: any
# failure to patch (unwritable dir, upstream guard literal changed) WARNs
# and falls back to the outer purge above rather than aborting the build --
# this is defense-in-depth, not the sole protection for the primary path.
# Ref: docs/requests/agent_status/atm339_vlc_stale_builddir_resume.md §3;
#      docs/research/atm339_stale_builddir/gate_atm339_builddir_isolation.sh
#      (CHECK_B / CHECK_C / CHECK_D); test_atm339_reconfigure_detection.sh CASE4.
_atm339_patch_inner_guard() {
    # $1 = path to compile-libvlc.sh. Returns: 0 = patched/already-patched/
    # nothing-to-do; 2 = guard literal not found (upstream changed, non-fatal);
    # 1 = unexpected failure (mktemp/awk/mv, non-fatal).
    local _atm339_c="$1"
    [ -f "$_atm339_c" ] || return 0
    grep -q -- "ATM339-INNER-GUARD-PATCH" "$_atm339_c" 2>/dev/null && return 0
    local _atm339_og='if [ ! -e $VLC_BUILD_DIR/config.h -o "$AVLC_RELEASE" = 1 ]; then'
    grep -qF -- "$_atm339_og" "$_atm339_c" 2>/dev/null || return 2
    local _atm339_snip
    _atm339_snip="$(mktemp)" || return 1
    # QUOTED heredoc: bash performs ZERO expansion, so the injected text keeps
    # compile-libvlc.sh's OWN native (unescaped) $VLC_BUILD_DIR / $VLC_SRC_DIR /
    # $TARGET_TUPLE syntax verbatim.
    cat > "$_atm339_snip" <<'ATM339_INNER_GUARD_EOF'
VLC_EXPECTED_CONTRIB_PREFIX="${VLC_SRC_DIR}/contrib/${TARGET_TUPLE}"
if [ -e "$VLC_BUILD_DIR/config.status" ] && ! grep -q -- "$VLC_EXPECTED_CONTRIB_PREFIX" "$VLC_BUILD_DIR/config.status" 2>/dev/null; then
    rm -rf "$VLC_BUILD_DIR"
    mkdir -p "$VLC_BUILD_DIR"
fi  # ATM339-INNER-GUARD-PATCH
ATM339_INNER_GUARD_EOF
    local _atm339_mode
    _atm339_mode="$(stat -c '%a' "$_atm339_c" 2>/dev/null || echo 755)"
    local _atm339_tmp
    _atm339_tmp="$(mktemp "$(dirname "$_atm339_c")/.atm339_patch.XXXXXX" 2>/dev/null)" || { rm -f "$_atm339_snip"; return 1; }
    if ! awk -v snippet="$_atm339_snip" -v guard="$_atm339_og" '
            $0 == guard { while ((getline line < snippet) > 0) print line; close(snippet) }
            { print }
        ' "$_atm339_c" > "$_atm339_tmp"; then
        rm -f "$_atm339_snip" "$_atm339_tmp"
        return 1
    fi
    mv "$_atm339_tmp" "$_atm339_c" 2>/dev/null || { rm -f "$_atm339_snip" "$_atm339_tmp"; return 1; }
    chmod "$_atm339_mode" "$_atm339_c" 2>/dev/null || true
    rm -f "$_atm339_snip"
    grep -q -- "ATM339-INNER-GUARD-PATCH" "$_atm339_c" 2>/dev/null || return 1
    return 0
}

if [ -n "$_vlc_src_dir" ]; then
    _atm339_compile_libvlc="$_vlc_src_dir/buildsystem/compile-libvlc.sh"
    if _atm339_patch_inner_guard "$_atm339_compile_libvlc"; then
        _atm339_rc=0
    else
        _atm339_rc=$?
    fi
    case "$_atm339_rc" in
        0) : ;;
        2) echo "[ATMOSphere-VLC] ATM-339: old guard literal not found verbatim in $_atm339_compile_libvlc (upstream changed?) -- skipping inner patch; the outer purge above still applies" ;;
        *) echo "[ATMOSphere-VLC] WARNING: ATM-339 inner guard patch failed for $_atm339_compile_libvlc (non-fatal; outer purge above still applies)" ;;
    esac
    if [ -f "$_atm339_compile_libvlc" ] && grep -q -- "ATM339-INNER-GUARD-PATCH" "$_atm339_compile_libvlc" 2>/dev/null; then
        echo "[ATMOSphere-VLC] ATM-339: inner reconfigure-guard patch is present in $_atm339_compile_libvlc"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────
# GCC-15 / C23 build-fix (ATMOSphere) — nasm 2.14 host-tool build.
# ─────────────────────────────────────────────────────────────────────────
# Host GCC >= 15 defaults to -std=gnu23 (C23), where `bool` is a native
# keyword. VLC's host-tool bootstrap (vlc/extras/tools) builds nasm 2.14
# from source. nasm 2.14's autoconf AC_HEADER_STDBOOL test FAILS under the
# C23 default, leaving HAVE_STDBOOL_H UNDEFINED + HAVE__BOOL defined, so
# include/compiler.h takes the `#elif defined(HAVE__BOOL)` branch whose
# line 166 is a latent nasm source bug (`#  typedef _Bool bool`, parsed as
# an invalid `#typedef` preprocessing directive) →
# `error: invalid preprocessing directive #typedef` → the host nasm build
# aborts → tools.mak `.buildnasm` fails → the whole VLC fork build fails.
# The canonical distro fix (openSUSE GCC-15 packaging, conan-center-index
# nasm/2.14 #3996, trofi "gcc-15 switched to C23") is to compile the
# affected host tool under a pre-C23 standard: passing CFLAGS="-std=gnu17"
# to nasm's ./configure makes AC_HEADER_STDBOOL pass → HAVE_STDBOOL_H
# defined → the good `#include <stdbool.h>` branch is taken; the remaining
# nasm compile then builds cleanly (warnings only) under the default gnu23.
# Root cause PROVEN (§11.4.6, reproduced on host gcc 15.2.1,
# __STDC_VERSION__ 202311L: config.h HAVE_STDBOOL_H flips undef→1 with the
# flag, and `make` then builds nasm 2.14 with rc=0).
#
# tools.mak is part of the FETCHED VLC source (vlc/, .gitignore'd; get-vlc.sh
# only RESETS it on a fresh clone or explicit --reset, and leaves a warm tree
# untouched), so a one-time hand-edit would be silently LOST on a fresh
# clone/re-init — the SAME reasoning as the CMAKE_POLICY_VERSION_MINIMUM and
# ATM-339 fixes above. This step re-applies the fix idempotently on EVERY
# invocation, guarded by the GCC15-NASM-C23-COMPAT marker. It is a GENERIC
# toolchain-compat fix — NO ATMOSphere-specific context (§11.4.28(B)
# decoupling). Non-fatal: any failure WARNs and falls through (the nasm
# build then fails loudly, as before).
_gcc15_patch_nasm_tools_mak() {
    # $1 = path to VLC extras/tools/tools.mak. Returns 0 = patched / already-
    # patched / nothing-to-do; 2 = target recipe line not found verbatim
    # (upstream changed, non-fatal); 1 = unexpected failure (non-fatal).
    local _mak="$1"
    [ -f "$_mak" ] || return 0
    grep -q -- "GCC15-NASM-C23-COMPAT" "$_mak" 2>/dev/null && return 0
    grep -qE '^\.buildnasm:' "$_mak" 2>/dev/null || return 2
    local _mode
    _mode="$(stat -c '%a' "$_mak" 2>/dev/null || echo 644)"
    local _tmp
    _tmp="$(mktemp "$(dirname "$_mak")/.gcc15nasm.XXXXXX" 2>/dev/null)" || return 1
    # Append CFLAGS="-std=gnu17" ONLY to the ./configure line INSIDE the
    # .buildnasm target block. tools.mak has many identical
    # `cd $<; ./configure --prefix=$(PREFIX)` lines for other tools, so the
    # match is strictly scoped to the .buildnasm recipe. The trailing
    # `# GCC15-NASM-C23-COMPAT` is a shell comment on the recipe line (make
    # passes recipe lines verbatim to the shell) — harmless + greppable for
    # idempotency.
    if ! awk '
            /^\.buildnasm:/ { innasm=1 }
            innasm && !done && /cd \$<; \.\/configure --prefix=\$\(PREFIX\)$/ {
                print $0 " CFLAGS=\"-std=gnu17\"  # GCC15-NASM-C23-COMPAT"
                done=1; innasm=0; next
            }
            /^[^[:blank:]#]/ && !/^\.buildnasm:/ { innasm=0 }
            { print }
        ' "$_mak" > "$_tmp"; then
        rm -f "$_tmp"; return 1
    fi
    grep -q -- "GCC15-NASM-C23-COMPAT" "$_tmp" 2>/dev/null || { rm -f "$_tmp"; return 2; }
    mv "$_tmp" "$_mak" 2>/dev/null || { rm -f "$_tmp"; return 1; }
    chmod "$_mode" "$_mak" 2>/dev/null || true
    return 0
}

if [ -n "$_vlc_src_dir" ]; then
    _gcc15_nasm_mak="$_vlc_src_dir/extras/tools/tools.mak"
    if _gcc15_patch_nasm_tools_mak "$_gcc15_nasm_mak"; then
        echo "[ATMOSphere-VLC] GCC15-NASM-C23-COMPAT: nasm ./configure gets CFLAGS=-std=gnu17 in $_gcc15_nasm_mak"
    else
        _gcc15_rc=$?
        case "$_gcc15_rc" in
            2) echo "[ATMOSphere-VLC] GCC15-NASM-C23-COMPAT: .buildnasm recipe not found verbatim in $_gcc15_nasm_mak (upstream changed?) — skipping (non-fatal; nasm build may fail under host gcc>=15)" ;;
            *) echo "[ATMOSphere-VLC] WARNING: GCC15-NASM-C23-COMPAT patch failed for $_gcc15_nasm_mak (non-fatal; nasm build may fail under host gcc>=15)" ;;
        esac
    fi
fi

# ─────────────────────────────────────────────────────────────────────────
# Container↔host contrib-prefix relocation (ATM-745).
# ─────────────────────────────────────────────────────────────────────────
# VLC's contrib install tree (contrib/<tuple>/) bakes its build-time ABSOLUTE
# prefix into every pkg-config .pc (Cflags/Libs), every libtool .la, every
# *-config helper script, and any generated *.cmake. When contrib is built
# inside the §12.9 container (AOSP tree mounted at /aosp) and the build is then
# re-run on the HOST (tree at its real path, /aosp absent), those baked prefixes
# point at the non-existent /aosp/... — so `pkg-config --cflags opus` / `... oapv`
# return `-I/aosp/.../include/opus` / `.../include/oapv`, dirs that do not exist.
# opus + oapv fail FIRST because their VLC modules do a BARE `#include <opus.h>`
# / `#include <oapv.h>` and reach the header ONLY via that .pc-provided subdir
# -I (their headers install into include/opus/ and include/oapv/, not include/
# directly) →
#   modules/codec/opus.c:39:   fatal error: 'opus.h' file not found
#   modules/codec/openapv.c:20: fatal error: 'oapv.h' file not found
# (every other contrib reaches its header via the base -I<prefix>/include the
# modules build adds itself with the correct host path). The companion
# build-android-<tuple>/config.status host↔container mismatch is already
# wiped+reconfigured by the ATM-343 outer purge + ATM-339 inner guard above;
# this step fixes the INSTALL tree those defenses do NOT touch.
#
# Fix: VLC ships its OWN canonical relocation tool for exactly this (prebuilt
# contribs are downloaded with a server-set prefix) — contrib/src/change_prefix.sh
# (invoked by contrib/src/main.mak:580 `cd $(PREFIX) && change_prefix.sh` for the
# `prebuilt` target). Reuse it verbatim (§11.4.8 — no reinvention): detect any
# baked .pc `prefix=` root that differs from the install dir's real host path and
# run change_prefix.sh <old> <new>. It rewrites bin/*, lib/*.la, lib/pkgconfig/*.pc;
# it does NOT touch lib/cmake/**/*.cmake, so extend to those. Idempotent by the
# mismatch check (already-host-correct → no-op) — heals host→container AND
# container→host in either direction. GENERIC toolchain-relocation, NO ATMOSphere
# context (§11.4.28(B) decoupling). Non-fatal: any failure WARNs and the build
# then fails loudly at the same opus/oapv step, as before.
# Root cause PROVEN (§11.4.6): all 68 .pc + 30 .la + 4 *-config + 1 .cmake baked
# prefix=/aosp/...; /aosp absent on host; post-relocation `pkg-config --cflags
# opus oapv` resolves to the host include/opus + include/oapv dirs that EXIST and
# contain opus.h / oapv.h.
_relocate_contrib_prefix() {
    # $1 = VLC source dir containing contrib/. Non-fatal on every path.
    local _src="$1"
    [ -d "$_src/contrib" ] || return 0
    local _cp="$_src/contrib/src/change_prefix.sh"
    if [ ! -f "$_cp" ]; then
        echo "[ATMOSphere-VLC] ATM-745: change_prefix.sh absent ($_cp) — skipping contrib relocation (non-fatal)"
        return 0
    fi
    local _pcdir _root _new _olds _o _cm
    for _pcdir in "$_src"/contrib/*/lib/pkgconfig; do
        [ -d "$_pcdir" ] || continue
        _root="$(cd "$_pcdir/../.." 2>/dev/null && pwd -P)" || continue
        [ -n "$_root" ] || continue
        _new="$_root"
        # distinct baked .pc prefixes that differ from the real host install root
        _olds="$(grep -h '^prefix=' "$_pcdir"/*.pc 2>/dev/null | sed 's/^prefix=//' | sort -u | grep -vxF "$_new" || true)"
        [ -n "$_olds" ] || continue   # already host-correct → idempotent no-op
        printf '%s\n' "$_olds" | while IFS= read -r _o; do
            [ -n "$_o" ] || continue
            echo "[ATMOSphere-VLC] ATM-745: relocating contrib prefix (container↔host):"
            echo "[ATMOSphere-VLC]   old: $_o"
            echo "[ATMOSphere-VLC]   new: $_new"
            if ! ( cd "$_root" && sh "$_cp" "$_o" "$_new" ) >/dev/null 2>&1; then
                echo "[ATMOSphere-VLC] WARNING: ATM-745 change_prefix.sh failed for '$_o' (non-fatal)"
            fi
            # change_prefix.sh omits *.cmake — extend for completeness.
            find "$_root" -name '*.cmake' -type f 2>/dev/null | while IFS= read -r _cm; do
                if grep -q -- "$_o" "$_cm" 2>/dev/null; then
                    sed -i "s,$_o,$_new,g" "$_cm" 2>/dev/null || true
                    echo "[ATMOSphere-VLC]   (cmake) $_cm"
                fi
            done || true
        done || true
    done
    return 0
}

if [ -n "$_vlc_src_dir" ]; then
    _relocate_contrib_prefix "$_vlc_src_dir"
fi

# ─────────────────────────────────────────────────────────────────────────
# VLC host-tools PATH + container↔host medialibrary re-setup (ATM-755).
# ─────────────────────────────────────────────────────────────────────────
# Two coupled container→host reuse defects in the medialibrary sub-build,
# both surfacing only now that ATM-745 lets the build reach medialibrary:
#
# (A) PATH-scoping bug in buildsystem/compile-medialibrary.sh — it exports
#     PATH="…/vlc/extras/tools/build/bin:$PATH" (where its meson wrapper +
#     ninja live) ONLY inside the `if [ ! -d build-android-<abi> ] ||
#     [ ! -f …/build.ninja ]` meson-SETUP block (compile-medialibrary.sh:196),
#     but `meson compile` / `meson install` (:221-222) run UNCONDITIONALLY
#     outside it. Whenever the setup block is skipped (a warm/valid
#     build-android dir), meson is NOT on PATH →
#       compile-medialibrary.sh: line 221: meson: command not found
#     (VLC's extras/tools DID build meson+ninja — .buildmeson/.buildninja
#     stamps present — so this is a PATH gap, not a missing tool). Put the
#     VLC host-tools bin on PATH for the WHOLE compile.sh chain here so meson
#     is found regardless of the sub-script's conditional scoping. Durable:
#     also fixes every REPEAT host build (where a host-valid warm dir
#     legitimately skips setup and would otherwise re-hit the PATH gap).
#
# (B) The reused medialibrary build-android-<abi>/build.ninja is container-
#     configured: it bakes the §12.9 container prefix /aosp/... (75 refs, 0
#     host refs) for the compiler/include/contrib paths. Even with meson on
#     PATH (A), `meson compile` against that build.ninja would fail (all
#     -I/-L point at the non-existent /aosp/...). Wipe a build-android dir
#     whose build.ninja references a contrib/build-android path NOT under the
#     host root so the setup block re-runs and regenerates build.ninja with
#     HOST paths — the medialibrary analogue of the ATM-343 libvlc
#     build-android purge above. Only a foreign-configured dir is wiped (a
#     valid host dir is preserved → no needless full medialibrary
#     reconfigure on repeat runs).
#
# GENERIC toolchain fixes, NO ATMOSphere context (§11.4.28(B)). Root cause
# PROVEN (§11.4.6): compile-medialibrary.sh:195-212 scopes the PATH export;
# the reused build.ninja has 75 /aosp refs and 0 host refs.
if [ -n "$_vlc_src_dir" ] && [ -d "$_vlc_src_dir/extras/tools/build/bin" ]; then
    export PATH="$_vlc_src_dir/extras/tools/build/bin:$PATH"
    echo "[ATMOSphere-VLC] ATM-755(A): VLC host-tools on PATH: $_vlc_src_dir/extras/tools/build/bin (meson/ninja/nasm/…)"
fi
for _mlbdir in "$SCRIPT_DIR"/medialibrary/medialibrary/build-android-*; do
    [ -d "$_mlbdir" ] || continue
    _mlbn="$_mlbdir/build.ninja"
    [ -f "$_mlbn" ] || continue   # no build.ninja → setup re-runs anyway
    _mlforeign="$( { grep -oE '/[A-Za-z0-9._/+-]*/(contrib|build-android)[A-Za-z0-9._/+-]*' "$_mlbn" 2>/dev/null \
        | grep -vE "^${SCRIPT_DIR}/" | sort -u | head -1 ; } || true )"
    if [ -n "$_mlforeign" ]; then
        echo "[ATMOSphere-VLC] ATM-755(B): wiping container-configured medialibrary build dir (foreign path in build.ninja):"
        echo "[ATMOSphere-VLC]   $_mlbdir (e.g. '$_mlforeign' not under '$SCRIPT_DIR')"
        rm -rf "$_mlbdir"
    fi
done

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
