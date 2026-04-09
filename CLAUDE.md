# CLAUDE.md - ATMOSphere VLC Player

Fork of VLC for Android, customized for ATMOSphere firmware on Orange Pi 5 Max (RK3588). Provides video and audio playback with native codec support.

## Project Overview

- **Package**: `atmosphere.videolan.vlc`
- **Language**: Kotlin/Java + C/C++ (libvlc native)
- **Build**: Gradle (AGP 8.13.2, Kotlin 2.1.20)
- **Repo**: `git@github.com:ATMOSphere1234321/ATMOSphere-VLC-Player.git`
- **Parent repo path**: `device/rockchip/atmosphere/vlc-player`
- **Upstream**: VideoLAN VLC for Android

### Key Directories

| Directory | Purpose |
|-----------|---------|
| `application/` | Android app module (UI, playback, settings) |
| `libvlcjni/` | JNI bridge to libvlc native library |
| `medialibrary/` | Media library scanner and database |
| `buildsystem/` | Build configuration and compile scripts |

### ATMOSphere Integration

- Listed in `VIDEO_PACKAGES` in VideoPlaybackDetector for Tier 2 task-move detection
- Uses native FFmpeg codecs (not Android MediaCodec) for most formats
- DEFLATED native libs injected into system.img via debugfs_static pipeline
- 32-bit APK (armeabi-v7a) used to avoid spdlog crash on arm64

## MANDATORY DEVELOPMENT PRINCIPLES

1. **Solutions MUST NOT be error-prone** -- every fix must be robust, not introduce new failure modes
2. **No blocking operations inside synchronized blocks** -- Thread.sleep(), network calls, or long computations inside `synchronized` WILL cause deadlocks
3. **Always consider concurrent callers** -- multiple media sessions can be active simultaneously
4. **Test the fix, not just the symptom** -- verify the fix works AND does not break anything else

## MANDATORY API KEY & SECRETS CONSTRAINTS

1. **NEVER commit `.env` files** -- they contain API keys and credentials
2. **NEVER add API keys to source code** -- use environment variables or `.env` files only
3. **ALWAYS verify `.gitignore` protects `.env`** before committing

## MANDATORY COMMIT & PUSH CONSTRAINTS

1. **ONLY use the official commit script from the PARENT repo**: `bash scripts/commit_all.sh "message"`
2. **NEVER use `git add`, `git commit`, or `git push` directly** in this submodule
3. The parent script handles staging, committing, and pushing to ALL remotes

## MANDATORY SUBMODULE SYNC CONSTRAINTS

1. **ALWAYS fetch and pull latest from upstream** before pushing our committed changes
2. **Analyze all new features/APIs** from upstream and incorporate them properly
3. **Merge conflicts** must be resolved carefully -- never discard upstream changes blindly

## MANDATORY TAGGING CONSTRAINTS

1. **Tags are NEVER created before flashing and validating** on BOTH ATMOSphere devices
2. **Tags MUST be applied to ALL owned submodules** when tagging the main repo
3. **Tag naming**: `<major>.<minor>.<patch>-dev[-<sub-version>]`

## Project Context

- Part of ATMOSphere Android 15 firmware for Orange Pi 5 Max (RK3588)
- Parent repo at `/run/media/milosvasic/DATA4TB/Projects/Android_15/` handles build, flash, and test
- Build via parent: `bash scripts/build.sh --skip-pull --skip-tests --skip-ota`
- Tests via parent: `bash device/rockchip/rk3588/tests/pre_build_verification.sh`
- SMB/CIFS network browsing supported (kernel CIFS module enabled)
