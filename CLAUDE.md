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

## MANDATORY HOST-SESSION SAFETY (Constitution §12)

**Forensic incident, 2026-04-27 22:22:14 (MSK):** the developer's
`user@1000.service` was SIGKILLed under an OOM cascade triggered by
`pip3 install --user openai-whisper` running on top of chronic
podman-pod memory pressure. The cascade SIGKILLed gnome-shell, every
ssh session, claude-code, tmux, btop, npm, node, java, pip3 — full
session loss. Evidence: `journalctl --since "2026-04-27 22:00"
--until "2026-04-27 22:23"`.

This invariant applies to **every script, test, helper, and AI agent**
in this submodule. Non-compliance is a release blocker.

### Forbidden — directly OR indirectly

1. **Suspending the host**: `systemctl suspend`, `pm-suspend`,
   `loginctl suspend`, DBus `org.freedesktop.login1.Suspend`,
   GNOME idle-suspend, lid-close handler.
2. **Hibernating / hybrid-sleeping**: any `Hibernate` / `HybridSleep`
   / `SuspendThenHibernate` method.
3. **Logging out the user**: `loginctl terminate-session`,
   `pkill -u <user>`, `systemctl --user --kill`, anything that
   signals `user@<uid>.service`.
4. **Unbounded-memory operations** inside `user@<uid>.service`
   cgroup. Any single command expected to exceed 4 GB RSS MUST be
   wrapped in `bounded_run` (defined in
   `scripts/lib/host_session_safety.sh`, parent repo).
5. **Programmatic rfkill toggles, lid-switch handlers, or
   power-button handlers** — these cascade into idle-actions.
6. **Disabling systemd-logind, GDM, or session managers** "to make
   things faster" — even temporary stops leave the system unable to
   recover the user session.

### Required safeguards

Every script in this submodule that performs heavy work (build,
transcription, model inference, large compression, multi-GB git op)
MUST:

1. Source `scripts/lib/host_session_safety.sh` from the parent repo.
2. Call `host_check_safety` at the top and **abort if it fails**.
3. Wrap any subprocess expected to exceed ~4 GB RSS in
   `bounded_run "<name>" <max-mem> <max-time> -- <cmd...>` so the
   kernel OOM killer is contained to that scope and cannot escalate
   to user.slice.
4. Cap parallelism (`-j`) to fit available RAM (each AOSP job ≈ 5 GB
   peak RSS).

### Container hygiene

Containers (Docker / Podman) we own or rely on MUST:

1. Declare an explicit memory limit (`mem_limit` / `--memory` /
   `MemoryMax`).
2. Set `OOMPolicy=stop` in their systemd unit to avoid retry loops.
3. Use exponential-backoff restart policies, never immediate retry.
4. Be clean-slate destroyed (`podman pod stop && rm`, `podman
   volume prune`) and rebuilt after any host crash or session loss
   so stale lock files don't keep producing failures.

### When in doubt

Don't run heavy work blind. Check `journalctl -k --since "1 hour ago"
| grep -c oom-kill`. If it's non-zero, **fix the offending workload
first**. Do not stack new work on a host already in distress.

**Cross-reference:** parent `docs/guides/ATMOSPHERE_CONSTITUTION.md`
§12 (full forensic, library API, operator directives) +
parent `scripts/lib/host_session_safety.sh`.

## MANDATORY ANTI-BLUFF VALIDATION (Constitution §8.1 + §11)

**This submodule inherits the parent ATMOSphere project's anti-bluff covenant.
A test that PASSes while the feature it claims to validate is unusable to an
end user is the single most damaging failure mode in this codebase. It has
shipped working-on-paper / broken-on-device builds before, and that MUST NOT
happen again.**

The canonical authority is `docs/guides/ATMOSPHERE_CONSTITUTION.md` §8.1
("NO BLUFF — positive-evidence-only validation") and §11 ("Bleeding-edge
ultra-perfection") in the parent repo. Every contribution to THIS submodule
is bound by it. Summarised non-negotiables:

1. **Tests MUST validate user-visible behaviour, not just metadata.** A gate
   that greps for a string in a config XML, an XML attribute, a manifest
   entry, or a build-time symbol is METADATA — not evidence the feature
   works for the end user. Such a gate is allowed ONLY when paired with a
   runtime / on-device test that exercises the user-visible path and reads
   POSITIVE EVIDENCE that the behaviour actually occurred (kernel `/proc/*`
   runtime state, captured audio/video, dumpsys output produced *during*
   playback, real input-event delivery, real surface composition, etc).
2. **PASS / FAIL / SKIP must be mechanically distinguishable.** SKIP is for
   environment limitations (no HDMI sink, no USB mic, geo-restricted endpoint
   unreachable) and MUST always carry an explicit reason. PASS is reserved
   for cases where positive evidence was observed. A test that completes
   without observing evidence MUST NOT report PASS.
3. **Every gate MUST have a paired mutation test in
   `scripts/testing/meta_test_false_positive_proof.sh` (parent repo).** The
   mutation deliberately breaks the feature and the gate MUST then FAIL.
   A gate without a paired mutation is a BLUFF gate and is a Constitution
   violation regardless of how many checks it appears to make.
4. **Challenges (HelixQA) and tests are in the same boat.** A Challenge that
   reports "completed" by checking the test runner exited 0, without
   observing the system behaviour the Challenge is supposed to verify, is a
   bluff. Challenge runners MUST cross-reference real device telemetry
   (logcat, captured frames, network probes, kernel state) to confirm the
   user-visible promise was kept.
5. **The bar for shipping is not "tests pass" but "users can use the feature."**
   If the on-device experience does not match what the test claims, the test
   is the bug. Fix the test (positive-evidence harder), do not silence it.
6. **No false-success results are tolerable.** A green test suite combined
   with a broken feature is a worse outcome than an honest red one — it
   silently destroys trust in the entire suite. Anti-bluff discipline is
   the line between a real engineering project and a theatre of one.

When in doubt: capture runtime evidence, attach it to the test result, and
let a hostile reviewer (i.e. yourself, in six months) try to disprove that
the feature really worked. If they can, the test is bluff and must be hardened.

**Cross-references:** parent CLAUDE.md "MANDATORY DEVELOPMENT PRINCIPLES",
parent AGENTS.md "NO BLUFF" section, parent `scripts/testing/meta_test_false_positive_proof.sh`.

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

---

## MANDATORY: ATMOSphere Constitution compliance (appended 2026-04-19 — ATMOSphere 1.1.3-dev-0.0.6)

Every change in this submodule MUST comply with the canonical
Constitution at `docs/guides/ATMOSPHERE_CONSTITUTION.md` in the parent
repo. In summary:

1. **Test coverage for every change** — pre-build gate (CM-MC*),
   post-build gate, on-device test, and a mutation entry in
   `scripts/testing/meta_test_false_positive_proof.sh` proving the
   gate catches regressions.
2. **Device validation before any tag** — both D1 and D2 flashed and
   green on every relevant suite.
3. **Commit + push via `bash scripts/commit_all.sh "…"` from the
   parent repo root.** Submodule source changes are committed in the
   submodule itself first, pushed to every remote of that submodule,
   and then the parent's `commit_all.sh` captures the updated
   pointer.
4. **Tags cascade.** Every version tag on the main repo is mirrored
   on this submodule at its current HEAD, across every remote this
   submodule publishes to. Use
   `scripts/testing/release_tag.sh <tag>` from the parent repo.
5. **Changelog discipline.** `docs/changelogs/<tag>.{md,html,json,txt}`
   on the parent repo documents every release; exported via
   `scripts/testing/export_changelog.sh`.
6. **No false-success results.** Tests that are always-PASS are
   immediately rewritten. Meta-test mutations catch bluff gates.
7. **Flock.** `commit_all.sh` and `push_all.sh` are serialised via
   `.git/.commit_all.lock` / `.git/.push_all.lock`. Never bypass.

Non-compliance is a blocker regardless of context.


## MANDATORY ABSOLUTE DATA SAFETY — ZERO RISK (Constitution §9)

**EVERY destructive repository operation** (history rewrite, force-push,
branch deletion, bulk file removal, submodule de-init, object pruning) MUST
follow Constitution §9 without exception:

1. **Hardlinked backup first** — near-instant (`cp -al .git <backup>/repo.git.mirror`),
   zero extra disk. No excuse to skip. Parent-repo helper:
   `scripts/testing/safe_history_rewrite.sh --pre-op`.
2. **Record pre-op metadata** — refs, tags, submodule pointers, HEAD commit,
   HEAD tree hash, HEAD tree content sha256.
3. **Run the operation** — never with hook-bypassing flags unless the user
   has explicitly authorized them for that exact operation.
4. **Post-op gate** — HEAD tree byte-identical (unless explicitly expected
   to change), all tags preserved, all submodule pointers intact, all
   domain-specific integrity checks pass. ANY failure → restore immediately
   from the hardlinked backup.
5. **Force-push is NEVER automatic** — `push_all.sh` (in parent repo) must
   not force-push as a failure-recovery path. Every force-push requires
   explicit per-session human authorization AND a passing §9 post-op gate.
6. **Audit trail** — force-push events recorded in parent repo
   `docs/changelogs/<tag>.md`.

Data-safety violations are catastrophic (irreversible once the remote GCs
dangling objects) and block the release cycle until fully remediated.

## MANDATORY ANTI-BLUFF COVENANT — END-USER QUALITY GUARANTEE (User mandate, 2026-04-28)

**Forensic anchor — direct user mandate (verbatim):**

> "We had been in position that all tests do execute with success and all Challenges as well, but in reality the most of the features does not work and can't be used! This MUST NOT be the case and execution of tests and Challenges MUST guarantee the quality, the completion and full usability by end users of the product!"

This is the historical origin of the project's anti-bluff covenant.
Every test, every Challenge, every gate, every mutation pair exists
to make the failure mode (PASS on broken-for-end-user feature)
mechanically impossible.

**Operative rule:** the bar for shipping is **not** "tests pass"
but **"users can use the feature."** Every PASS in this codebase
MUST carry positive evidence captured during execution that the
feature works for the end user. Metadata-only PASS, configuration-
only PASS, "absence-of-error" PASS, and grep-based PASS without
runtime evidence are all critical defects regardless of how green
the summary line looks.

**Tests AND Challenges (HelixQA) are bound equally** — a Challenge
that scores PASS on a non-functional feature is the same class of
defect as a unit test that does. Both must produce positive end-
user evidence; both are subject to the §8.1 five-constraint rule
and §11 captured-evidence requirement.

**Canonical authority:** parent
[`docs/guides/ATMOSPHERE_CONSTITUTION.md`](../../docs/guides/ATMOSPHERE_CONSTITUTION.md)
§8.1 (positive-evidence-only validation) + §11 (bleeding-edge
ultra-perfection quality bar) + §11.3 (the "no bluff" CLAUDE.md /
AGENTS.md mandate) + **§11.4 (this end-user-quality-guarantee
forensic anchor — propagation requirement enforced by pre-build
gate `CM-COVENANT-PROPAGATION`)**.

Non-compliance is a release blocker regardless of context.

