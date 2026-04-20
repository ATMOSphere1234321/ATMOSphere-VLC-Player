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
