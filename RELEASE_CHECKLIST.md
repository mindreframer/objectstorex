# ObjectStoreX Release Checklist

This document outlines the complete process for releasing a new version of ObjectStoreX with precompiled NIFs.

## Overview

The release process involves:
1. Pre-release verification
2. Version updates
3. Tag creation and CI build
4. Checksum generation
5. Hex package preparation
6. Publication to Hex.pm
7. Post-release verification

**Important:** All precompiled binaries are built automatically by GitHub Actions. Never build binaries manually.

---

## 1. Pre-Release Checks

Before starting the release process, ensure all quality checks pass:

### 1.1 Code Quality

```bash
# Run all tests
mix test

# Check formatting
mix format --check-formatted

# Compile without warnings
mix compile --warnings-as-errors

# Run Credo (if configured)
mix credo --strict

# Run Dialyzer (if configured)
mix dialyzer
```

**Checklist:**
- [ ] All tests passing
- [ ] Code properly formatted
- [ ] No compilation warnings
- [ ] No Credo issues (if applicable)
- [ ] No Dialyzer warnings (if applicable)

### 1.2 Local NIF Build

Test that the NIF compiles locally from source:

```bash
# Force local build
OBJECTSTOREX_BUILD=1 mix deps.get
OBJECTSTOREX_BUILD=1 mix compile

# Run tests with locally built NIF
OBJECTSTOREX_BUILD=1 mix test
```

**Checklist:**
- [ ] NIF compiles successfully from source
- [ ] All tests pass with locally built NIF
- [ ] No Rust compilation warnings

### 1.3 Rust Tests

Verify Rust-level tests pass:

```bash
cd native/objectstorex
cargo test
cargo test --release
cargo clippy -- -D warnings
cd ../..
```

**Checklist:**
- [ ] All Rust tests passing
- [ ] No Clippy warnings

### 1.4 Git Status

```bash
git status
git log --oneline -10
```

**Checklist:**
- [ ] Working directory clean (no uncommitted changes)
- [ ] All changes committed
- [ ] On correct branch (usually `main`)
- [ ] Branch up to date with remote

---

## 2. Version Update

### 2.1 Update Version Number

Edit `mix.exs`:

```elixir
@version "X.Y.Z"  # Update to new version
```

**Version Strategy:**
- **Patch release** (0.1.0 → 0.1.1): Bug fixes, no API changes
- **Minor release** (0.1.0 → 0.2.0): New features, backward compatible
- **Major release** (0.1.0 → 1.0.0): Breaking API changes

**Checklist:**
- [ ] Version number updated in `mix.exs`
- [ ] Version follows semantic versioning

### 2.2 Update CHANGELOG.md

Add entry for the new version with date:

```markdown
## [X.Y.Z] - YYYY-MM-DD

### Added
- New features

### Changed
- Modifications to existing features

### Fixed
- Bug fixes

### Security
- Security improvements
```

**Checklist:**
- [ ] CHANGELOG.md updated with new version
- [ ] All significant changes documented
- [ ] Date is correct
- [ ] Version matches `mix.exs`

### 2.3 Update README (if needed)

Review and update if version-specific information changed:
- Installation instructions
- API examples
- Platform support

**Checklist:**
- [ ] README reviewed
- [ ] Version-specific info updated (if applicable)

### 2.4 Commit Version Changes

```bash
git add mix.exs CHANGELOG.md README.md
git commit -m "Bump version to X.Y.Z"
git push origin main
```

**Checklist:**
- [ ] Version bump committed
- [ ] Pushed to remote

---

## 3. Tag Creation and CI Build

### 3.1 Create Git Tag

```bash
# Create annotated tag
git tag -a vX.Y.Z -m "Release version X.Y.Z"

# Verify tag
git tag -l vX.Y.Z
git show vX.Y.Z
```

**Checklist:**
- [ ] Tag created with correct version (vX.Y.Z format)
- [ ] Tag is annotated (not lightweight)
- [ ] Tag message is clear

### 3.2 Push Tag

```bash
# Push tag to GitHub (triggers CI build)
git push origin vX.Y.Z
```

**This will trigger the GitHub Actions workflow to build all 8 precompiled NIFs.**

**Checklist:**
- [ ] Tag pushed to remote
- [ ] GitHub Actions workflow triggered

### 3.3 Monitor CI Build

Visit: `https://github.com/YOUR_ORG/objectstorex/actions`

Wait for the NIF Release workflow to complete. This typically takes 20-30 minutes.

**Checklist:**
- [ ] All 8 build jobs succeeded:
  - [ ] aarch64-apple-darwin
  - [ ] x86_64-apple-darwin
  - [ ] aarch64-unknown-linux-gnu
  - [ ] x86_64-unknown-linux-gnu
  - [ ] aarch64-unknown-linux-musl
  - [ ] x86_64-unknown-linux-musl
  - [ ] x86_64-pc-windows-msvc
  - [ ] x86_64-pc-windows-gnu
- [ ] Artifacts uploaded
- [ ] Build attestations created
- [ ] GitHub Release created with all artifacts

### 3.4 Verify GitHub Release

Visit: `https://github.com/YOUR_ORG/objectstorex/releases/tag/vX.Y.Z`

**Checklist:**
- [ ] Release exists
- [ ] All 8 `.tar.gz` files present
- [ ] File names follow pattern: `objectstorex-vX.Y.Z-nif-2.15-{target}.tar.gz`
- [ ] Attestation badges present (for supported platforms)
- [ ] Files are downloadable

---

## 4. Checksum Generation

After all CI builds complete and artifacts are published to GitHub Release:

### 4.1 Download and Generate Checksums

```bash
# Generate checksums from GitHub Release
mix gen.checksum

# This runs: mix rustler_precompiled.download ObjectStoreX.Native --all --print
```

This command will:
1. Download all 8 precompiled NIFs from GitHub Release
2. Calculate SHA256 checksums
3. Create `checksum-Elixir.ObjectStoreX.Native.exs`

**Checklist:**
- [ ] `mix gen.checksum` executed successfully
- [ ] All 8 artifacts downloaded
- [ ] `checksum-Elixir.ObjectStoreX.Native.exs` created
- [ ] No download errors

### 4.2 Verify Checksum File

```bash
cat checksum-Elixir.ObjectStoreX.Native.exs
```

Expected format:

```elixir
%{
  "objectstorex-vX.Y.Z-nif-2.15-aarch64-apple-darwin.tar.gz" =>
    "sha256:abc123...",
  "objectstorex-vX.Y.Z-nif-2.15-x86_64-apple-darwin.tar.gz" =>
    "sha256:def456...",
  # ... all 8 targets
}
```

**Checklist:**
- [ ] Checksum file contains exactly 8 entries
- [ ] All target platforms present
- [ ] All checksums are 64-character hex strings
- [ ] Version in filenames matches release version

### 4.3 Keep Checksum File Local

**Important:** The checksum file should NOT be committed to git. It's listed in `.gitignore` and will be included in the Hex package automatically when you run `mix hex.build`.

**Checklist:**
- [ ] Checksum file exists locally
- [ ] File is NOT committed (should be ignored by git)

---

## 5. Hex Package Preparation

### 5.1 Build Hex Package

```bash
# Build package locally
mix hex.build

# This creates: objectstorex-X.Y.Z.tar
```

**Checklist:**
- [ ] Package built successfully
- [ ] `objectstorex-X.Y.Z.tar` created

### 5.2 Inspect Package Contents

```bash
# Extract and inspect
tar -tzf objectstorex-X.Y.Z.tar

# Or use hex.build with --unpack
mix hex.build --unpack
```

Verify the package includes:

**Required Files:**
- [ ] `lib/**/*.ex` - All Elixir source files
- [ ] `native/objectstorex/src/**/*.rs` - Rust source files
- [ ] `native/objectstorex/Cargo.toml` - Cargo manifest
- [ ] `native/objectstorex/Cargo.lock` - Cargo lock file
- [ ] `native/objectstorex/.cargo/config.toml` - Cargo configuration
- [ ] `native/objectstorex/Cross.toml` - Cross-compilation config
- [ ] `checksum-Elixir.ObjectStoreX.Native.exs` - Checksum file
- [ ] `mix.exs` - Mix project file
- [ ] `README.md` - Documentation
- [ ] `LICENSE` - License file
- [ ] `CHANGELOG.md` - Change history

**Excluded Files (should NOT be present):**
- [ ] `test/**` - Test files
- [ ] `.git/**` - Git metadata
- [ ] `_build/**` - Build artifacts
- [ ] `deps/**` - Dependencies
- [ ] `native/objectstorex/target/**` - Rust build artifacts

### 5.3 Dry Run Publish

```bash
# Test publish without actually publishing
mix hex.publish --dry-run
```

Review the output carefully:

**Checklist:**
- [ ] No errors or warnings
- [ ] Package size reasonable (<10 MB typically)
- [ ] All expected files included
- [ ] No unexpected files included
- [ ] Dependencies listed correctly

---

## 6. Hex Publication

### 6.1 Final Verification

Before publishing, triple-check:

**Checklist:**
- [ ] Version number is correct
- [ ] CHANGELOG.md is updated
- [ ] All tests pass
- [ ] All 8 precompiled NIFs available on GitHub Release
- [ ] Checksum file generated locally
- [ ] Package contents verified
- [ ] Dry run successful

### 6.2 Publish to Hex.pm

```bash
# Publish the package
mix hex.publish

# You will be prompted to:
# 1. Review package details
# 2. Confirm publication
# 3. Enter your Hex password (or use HEX_API_KEY)
```

**Important:** This action cannot be undone. You cannot delete or modify a published version.

**Checklist:**
- [ ] Package published successfully
- [ ] No errors during publication

### 6.3 Verify Hex.pm Page

Visit: `https://hex.pm/packages/objectstorex`

**Checklist:**
- [ ] New version visible on hex.pm
- [ ] README rendered correctly
- [ ] Package metadata correct
- [ ] Links working
- [ ] Installation instructions visible

---

## 7. Post-Release Verification

### 7.1 Test Installation (Precompiled)

Create a fresh test project:

```bash
cd /tmp
mix new test_objectstorex
cd test_objectstorex

# Add dependency
cat >> mix.exs <<'EOF'
  defp deps do
    [
      {:objectstorex, "~> X.Y.Z"}
    ]
  end
EOF

# Install (should download precompiled NIF)
mix deps.get
```

**Checklist:**
- [ ] Dependency resolves correctly
- [ ] Precompiled NIF downloaded (not built from source)
- [ ] No Rust compilation occurs
- [ ] Installation completes in <10 seconds

### 7.2 Test Basic Functionality

```elixir
# In test_objectstorex/lib/test.ex
defmodule Test do
  def run do
    # Test basic ObjectStoreX functionality
    {:ok, store} = ObjectStoreX.Native.new("local", %{path: "/tmp/test"})
    IO.puts("ObjectStoreX working! Store: #{inspect(store)}")
  end
end
```

```bash
mix run -e "Test.run()"
```

**Checklist:**
- [ ] Code compiles
- [ ] NIFs load successfully
- [ ] Basic operations work

### 7.3 Test Force Build

```bash
# Clean deps
mix deps.clean objectstorex
rm -rf deps/objectstorex

# Force local build
OBJECTSTOREX_BUILD=1 mix deps.get
OBJECTSTOREX_BUILD=1 mix compile
```

**Checklist:**
- [ ] Rust compilation occurs
- [ ] Build succeeds
- [ ] Tests pass with locally built NIF

### 7.4 Verify Documentation

Visit: `https://hexdocs.pm/objectstorex/X.Y.Z/`

**Checklist:**
- [ ] Documentation generated
- [ ] API docs complete
- [ ] README included
- [ ] Examples visible
- [ ] Links working

---

## 8. Announcement and Communication

### 8.1 Update Repository

**Checklist:**
- [ ] GitHub Release has release notes
- [ ] README updated if needed
- [ ] Issues/PRs referencing this release labeled
- [ ] Milestone closed (if applicable)

### 8.2 Communication (Optional)

**Checklist:**
- [ ] Announcement on project forum/chat
- [ ] Blog post (for major releases)
- [ ] Social media (for significant releases)
- [ ] Email to users (for breaking changes)

---

## 9. Troubleshooting

### Problem: CI build fails for some targets

**Solution:**
1. Check GitHub Actions logs for specific error
2. For cross-compilation errors, verify `Cross.toml` configuration
3. For linking errors, check `.cargo/config.toml` rustflags
4. Delete tag, fix issue, create new tag with patch version

### Problem: Checksum generation fails

**Solution:**
1. Verify all 8 artifacts exist in GitHub Release
2. Check artifact names match expected pattern
3. Verify GitHub Release is public (not draft)
4. Try clearing RustlerPrecompiled cache: `rm -rf ~/.cache/rustler_precompiled`

### Problem: Hex publish fails

**Solution:**
1. Check `mix hex.publish --dry-run` output
2. Verify version not already published: `mix hex.info objectstorex`
3. Check package files in `mix.exs` include all necessary files
4. Ensure checksum file committed to git

### Problem: Users report "NIF not loaded"

**Solution:**
1. Verify their platform is in supported targets (8 platforms)
2. Check GitHub Release has their platform's binary
3. Verify checksums are correct
4. Guide them to force local build: `OBJECTSTOREX_BUILD=1`

### Problem: Precompiled NIF not downloaded

**Solution:**
1. Check `base_url` in `lib/objectstorex/native.ex` is correct
2. Verify version in Native module matches git tag
3. Check GitHub Release is public
4. Try clearing cache: `rm -rf _build deps` and `mix deps.get`

---

## 10. Release Schedule Recommendations

### Patch Releases (X.Y.Z → X.Y.Z+1)
- Bug fixes only
- Can be released frequently (weekly if needed)
- Low risk

### Minor Releases (X.Y.0 → X.Y+1.0)
- New features, backward compatible
- Recommended: Monthly to quarterly
- Moderate testing needed

### Major Releases (X.0.0 → X+1.0.0)
- Breaking changes
- Recommended: Yearly or less frequent
- Extensive testing required
- Migration guide needed

---

## 11. Quick Reference

### Key Commands

```bash
# Pre-release checks
mix test && mix format --check-formatted && mix compile --warnings-as-errors

# Version update
# Edit mix.exs, CHANGELOG.md, README.md
git add mix.exs CHANGELOG.md README.md
git commit -m "Bump version to X.Y.Z"
git push

# Tag and trigger build
git tag -a vX.Y.Z -m "Release version X.Y.Z"
git push origin vX.Y.Z

# After CI completes: Generate checksums (keep local, don't commit)
mix gen.checksum

# Publish
mix hex.build
mix hex.publish --dry-run
mix hex.publish
```

### Important URLs

- **GitHub Actions**: `https://github.com/YOUR_ORG/objectstorex/actions`
- **GitHub Releases**: `https://github.com/YOUR_ORG/objectstorex/releases`
- **Hex.pm Package**: `https://hex.pm/packages/objectstorex`
- **HexDocs**: `https://hexdocs.pm/objectstorex`

### Critical Files

- `mix.exs` - Version number, dependencies, package config
- `CHANGELOG.md` - Release notes
- `lib/objectstorex/native.ex` - RustlerPrecompiled config
- `checksum-Elixir.ObjectStoreX.Native.exs` - Binary checksums
- `.github/workflows/nif-release.yml` - CI build config

---

## 12. Rollback Procedure

If a critical issue is discovered after release:

### Option 1: Yank the Release (Hex.pm)

```bash
# Retire the problematic version
mix hex.retire objectstorex X.Y.Z
```

**Note:** This doesn't delete the package but marks it as retired.

### Option 2: Immediate Patch Release

1. Fix the issue
2. Bump to X.Y.Z+1
3. Follow release process
4. Retire the problematic version

### Option 3: Revert to Previous Version

Users can pin to previous version in `mix.exs`:

```elixir
{:objectstorex, "~> X.Y.Z-1"}  # Previous version
```

---

## Summary

The complete release process:

1. ✅ **Pre-release**: All tests pass, code clean
2. ✅ **Version**: Update version, CHANGELOG, README
3. ✅ **Tag**: Create and push git tag (triggers CI)
4. ✅ **Wait**: CI builds all 8 precompiled NIFs (~30 min)
5. ✅ **Checksums**: Generate checksums locally (don't commit)
6. ✅ **Verify**: Build and inspect hex package
7. ✅ **Publish**: Publish to hex.pm
8. ✅ **Test**: Verify installation and functionality
9. ✅ **Announce**: Update docs, communicate release

**Time Estimate:** 2-3 hours (including CI build time)

**Remember:** The CI builds the binaries, not you. Never manually build and upload binaries.
