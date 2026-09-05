# Package pin parity

## Plan before changes

The audit found SwiftPM resolving ArgumentParser 1.7.0 while Xcode resolves
1.7.1. Use SwiftPM's resolver to select the existing Xcode pin (1.7.1) so both
build entry points use the same revision. Keep the package requirements,
Yams 5.4.0, and the dependency set unchanged.

The baseline already passes 330 SPM tests and the Xcode app baseline uses
1.7.1. After resolving, compare both lockfile pin arrays and run the full
SPM build/tests. Document resolver-specific origin hashes separately from
dependency revisions; the origin hashes need not match.

## Validation

- `swift package --scratch-path /tmp/framer-cleanup-build resolve
  swift-argument-parser --version 1.7.1` completed successfully.
- Both lockfiles' complete pin arrays are identical: ArgumentParser 1.7.1 at
  `626b5b7b2f45e1b0b1c6f4a309296d1d21d7311b`, Yams 5.4.0 unchanged.
- Full SPM build and **330 tests passed, zero failures/skips**. No package
  requirements or dependencies were added. SwiftPM refreshed its origin hash.
