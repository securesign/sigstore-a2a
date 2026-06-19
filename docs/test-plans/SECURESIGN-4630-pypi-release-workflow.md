# Test Plan: SECURESIGN-4630 — PyPI Release Workflow and Container Image

## Overview

- **Ticket:** [SECURESIGN-4630](https://redhat.atlassian.net/browse/SECURESIGN-4630)
- **Summary:** Downstream release workflow (`rh-release.yml`) that publishes `rh-sigstore-a2a` to PyPI via trusted publisher (OIDC), creates GitHub Releases, and builds + pushes a container image to GHCR.
- **Scope:**
  - `.github/workflows/rh-release.yml` — downstream release pipeline
  - `.github/workflows/release.yml` — upstream workflow (tag triggers disabled, manual dispatch only)
  - `Containerfile` — public base image (`python:3.13-slim`) for CI builds
  - `Containerfile.rh` — UBI9 base for future downstream production builds
  - `pyproject.toml` — package metadata (name, author, maintainer)

## Test Environment

| Resource | Details |
|----------|---------|
| GitHub Actions | Repository with `id-token: write` permissions and `pypi` environment configured |
| PyPI | Trusted publisher configured for `securesign/sigstore-a2a` repo, `rh-release.yml` workflow, `pypi` environment |
| GHCR | GitHub Container Registry under `securesign` org |
| Python | 3.11+ with `pip` for install verification |
| Docker/Podman | For container image pull and run verification |

## Prerequisites

1. PyPI trusted publisher configured for `rh-sigstore-a2a`
2. GitHub environment `pypi` exists on the repository
3. Version in `sigstore_a2a/__init__.py` matches the tag being pushed

## Test Scenarios

### TP-4630-01: Tag Pattern Triggers Correct Workflow

**Description:** Verify that `rhtas-v*` tags trigger `rh-release.yml` and NOT `release.yml`.

**Steps:**
1. Push a tag matching the `rhtas-v*` pattern (e.g., `rhtas-v0.0.1-rc2`).
2. Check GitHub Actions for workflow runs triggered by the tag.

**Expected Result:** Only `Downstream Release` workflow runs. `Release` workflow does NOT trigger.

**Pass/Fail:** PASS if only `rh-release.yml` triggers.

### TP-4630-02: Version Extraction and PEP 440 Normalization

**Description:** Verify that hyphenated prerelease tags are normalized to PEP 440 format.

**Steps:**
1. Set `__init__.py` version to `0.0.1rc2`.
2. Push tag `rhtas-v0.0.1-rc2`.
3. Check the "Extract version from tag" step output in the workflow run.

**Expected Result:** Extracted version is `0.0.1rc2` (hyphen removed). Version consistency check passes.

**Pass/Fail:** PASS if version extraction produces PEP 440 compliant version and consistency check passes.

### TP-4630-03: Version Consistency Check Rejects Mismatch

**Description:** Verify that a tag/version mismatch is caught before publishing.

**Steps:**
1. Set `__init__.py` version to `0.0.1rc1`.
2. Attempt to push tag `rhtas-v0.0.2-rc1` (mismatched version).
3. Check the build job output.

**Expected Result:** Build fails at "Verify version consistency" step with error message showing the mismatch.

**Pass/Fail:** PASS if build fails with a clear version mismatch error.

### TP-4630-04: PyPI Publish via Trusted Publisher (OIDC)

**Description:** Verify the package is published to PyPI using OIDC trusted publisher without API tokens.

**Steps:**
1. Push a valid release tag (e.g., `rhtas-v0.0.1-rc2`).
2. Check the "Publish to PyPI" job in the workflow run.
3. Verify the package appears on PyPI: https://pypi.org/project/rh-sigstore-a2a/

**Expected Result:** Publish job passes using `id-token: write` OIDC. No `PYPI_API_TOKEN` secret used. Package appears on PyPI.

**Pass/Fail:** PASS if publish succeeds via OIDC and package is visible on PyPI.

### TP-4630-05: Package Installable from PyPI

**Description:** Verify the published package is installable.

**Steps:**
1. After publish, run:
   ```bash
   pip install rh-sigstore-a2a==<version>
   ```
2. Verify the CLI is available:
   ```bash
   sigstore-a2a --version
   ```

**Expected Result:** Package installs successfully. CLI reports the correct version.

**Pass/Fail:** PASS if install succeeds and version matches.

### TP-4630-06: GitHub Release Created

**Description:** Verify a GitHub Release is created with build artifacts and release notes.

**Steps:**
1. After tag push, check https://github.com/securesign/sigstore-a2a/releases
2. Verify the release includes:
   - Wheel (`.whl`) and source distribution (`.tar.gz`) as assets
   - Auto-generated release notes
   - Prerelease flag set for `rc`/`beta`/`alpha` tags

**Expected Result:** Release exists with artifacts and correct prerelease status.

**Pass/Fail:** PASS if release exists with both distribution assets and correct prerelease flag.

### TP-4630-07: Container Image Built and Pushed to GHCR

**Description:** Verify the container image is built from `Containerfile` and pushed to GHCR.

**Steps:**
1. After release pipeline completes, pull the image:
   ```bash
   docker pull ghcr.io/securesign/sigstore-a2a:latest
   ```
2. Run the container:
   ```bash
   docker run --rm ghcr.io/securesign/sigstore-a2a:latest --version
   ```

**Expected Result:** Image pulls successfully. Container runs and reports the correct version.

**Pass/Fail:** PASS if image is pullable and CLI works inside the container.

### TP-4630-08: Build Provenance Attestation

**Description:** Verify build provenance attestation is generated for the container image.

**Steps:**
1. After release pipeline completes, check the "Generate artifact attestation" step.
2. Verify attestation is pushed to the registry.

**Expected Result:** Attestation step completes successfully.

**Pass/Fail:** PASS if attestation step passes.

### TP-4630-09: Upstream release.yml Disabled for Tags

**Description:** Verify the upstream `release.yml` does not trigger on tag pushes.

**Steps:**
1. Push a `rhtas-v*` tag.
2. Also verify that pushing a `v*` tag (if ever done) only triggers `release.yml` via manual `workflow_dispatch`, not automatic push.
3. Check that the PyPI publish job in `release.yml` is commented out.

**Expected Result:** `release.yml` has no `push.tags` trigger. PyPI publish job is disabled.

**Pass/Fail:** PASS if upstream workflow does not trigger on tags and PyPI publish is disabled.

### TP-4630-10: PyPI Metadata Accuracy

**Description:** Verify the PyPI project page shows correct author and maintainer.

**Steps:**
1. Visit https://pypi.org/project/rh-sigstore-a2a/
2. Check the Author and Maintainer fields.

**Expected Result:** Author is "Sigstore Authors" (sigstore-dev@googlegroups.com). Maintainer is "Sachin Sampras M".

**Pass/Fail:** PASS if metadata matches.

## Regression Tests

- Existing CI workflows (Core, Lint, Security, Tests) are unaffected by release changes.
- Unit tests (`make test`) pass — 49/49.
- The `v*` tag pattern no longer triggers any automatic workflow in the downstream fork.

## Release Gate Criteria

- TP-4630-01 (correct workflow trigger) passes.
- TP-4630-04 (PyPI publish via OIDC) passes.
- TP-4630-05 (package installable) passes.
- TP-4630-06 (GitHub Release created) passes.
- TP-4630-07 (container image pullable and runnable) passes.
- No regression in existing CI pipeline.
