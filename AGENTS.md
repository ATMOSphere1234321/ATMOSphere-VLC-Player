# AGENTS.md — vlc-player submodule (ATMOSphere 1.1.3-dev-0.0.6+)

Every AI agent working in this submodule MUST comply with the canonical
[ATMOSphere Constitution](../../../../../docs/guides/ATMOSPHERE_CONSTITUTION.md)
in the parent repo.

## Non-negotiable summary

1. **Tests for every change**: pre-build `CM-MC*` gate, post-build gate,
   on-device test, and a mutation entry in
   `scripts/testing/meta_test_false_positive_proof.sh` proving the gate
   catches regressions.
2. **Both devices flashed and green** before any tag.
3. **Commit + push via `bash scripts/commit_all.sh "…"` from the
   parent repo root.** For submodule source changes: commit inside the
   submodule first, push to every submodule remote, THEN run parent's
   `commit_all.sh` to capture the updated pointer.
4. **Tags cascade**: every main-repo tag mirrored on this submodule at
   its current HEAD, across every remote this submodule publishes to.
   Use `scripts/testing/release_tag.sh <tag>` from the parent.
5. **Changelog discipline**: every tag has `docs/changelogs/<tag>.md`
   + HTML + JSON + TXT exports (`scripts/testing/export_changelog.sh`).
6. **False-success results are literally impossible**: every gate has a
   mutation-test pair; any always-PASS gate is immediately rewritten.
7. **Flock is sacred**: `commit_all.sh` and `push_all.sh` are
   serialised via `.git/.commit_all.lock` / `.git/.push_all.lock`.
   Never bypass — concurrent invocations corrupt the split-archive
   temp-branch workflow.

Non-compliance is a blocker regardless of context. Refer to the
Constitution for full definitions, enforcement notes, and the canonical
commit / push / tag sequence.


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
