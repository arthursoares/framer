# Preserve unreadable presets

Parent branch: `chore/develop-cleanup`. Arthur requested continued fixes as
stacked PRs after the repository audit.

## Plan before implementation

1. Add regressions proving that listing still returns valid presets in sorted
   order but leaves malformed JSON, unsupported preset records, and directories
   with a `.json` suffix untouched. Run them against the existing deletion path.
2. Delete the automatic removal in `PresetStore.list()`. A listing cannot know
   whether unreadable data is corrupt, temporarily inaccessible, or produced by
   a newer version. Keep the existing skip-and-continue behavior for the list.
3. Update current project guidance so future edits do not restore deletion;
   preserve the historical lesson and the legacy-decoding requirement.
4. Run focused and full SPM tests, review, and open this PR above the cleanup PR.

No schema, recovery format, dependency, or UI change is needed. Manual deletion
remains available through the existing store API/filesystem. A recovery UI can
be designed separately without risking the original bytes.

## Verification

- Before the fix: both new tests failed, with four assertions proving that
  listing deleted malformed, unsupported, and empty JSON plus directory contents.
- After the fix: `swift build --scratch-path /tmp/framer-cleanup-build` and
  `swift test --scratch-path /tmp/framer-cleanup-build` passed: **317 tests,
  zero failures, zero skips, zero warnings**.
- Independent review found no implementation defects. Updated the remaining
  active config/run guidance and code comments identified by review; historical
  changelog entries remain unchanged.
- `git diff --check` passed. No serialization or rendering code changed.
