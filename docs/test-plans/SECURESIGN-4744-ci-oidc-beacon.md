# Test Plan: SECURESIGN-4744 — CI OIDC Beacon Fix

## Overview

- **Ticket:** [SECURESIGN-4744](https://redhat.atlassian.net/browse/SECURESIGN-4744)
- **Summary:** CI `sign-agent-card` job was failing intermittently because the `sigstore-conformance/extremely-dangerous-public-oidc-beacon` GitHub Action's token expired before use.
- **Scope:** `.github/workflows/ci.yml` — `sign-agent-card` job token acquisition, signing, and verification steps.
- **Fix:** Replaced the beacon action with a direct `curl` from GCS bucket, switched to `--staging`, and updated verify identity to Google SA credentials.

## Test Environment

| Resource | Details |
|----------|---------|
| GitHub Actions | CI pipeline on push to `main`/`develop` or on PR |
| Sigstore staging | Public staging infrastructure (no cluster needed) |
| GCS bucket | `storage.googleapis.com/sigstore-conformance-testing-token/untrusted-testing-token.txt` |

## Prerequisites

1. Push access to the repository (to trigger CI on `main`/`develop`) or a PR branch.
2. GitHub Actions enabled with `id-token: write` permissions.

## Test Scenarios

### TP-4744-01: CI sign-agent-card Job Passes on PR

**Description:** Verify the `sign-agent-card` CI job completes successfully when a PR is opened or updated.

**Steps:**
1. Open or update a PR targeting `main` or `develop`.
2. Monitor the GitHub Actions `Core` workflow.
3. Check the `sign-agent-card` job status.

**Expected Result:** The `sign-agent-card` job passes. All steps succeed: token fetch, sign GeoRoute, sign Data Analysis, verify GeoRoute, verify Data Analysis, upload artifacts.

**Pass/Fail:** PASS if the job completes with a green check.

### TP-4744-02: Token Fetch from GCS Bucket

**Description:** Verify the OIDC token is successfully fetched from the GCS bucket.

**Steps:**
1. In the CI logs, locate the "Fetch OIDC token" step.
2. Verify `curl` fetches from `storage.googleapis.com/sigstore-conformance-testing-token/untrusted-testing-token.txt`.
3. Verify `SIGSTORE_ID_TOKEN` is set in the environment (the token value will be masked in logs).

**Expected Result:** Step completes in under 5 seconds (no retries needed). Token is set.

**Pass/Fail:** PASS if step succeeds without retries.

### TP-4744-03: Sign with --staging and GCS Token

**Description:** Verify both Agent Cards are signed successfully using the GCS conformance token against Sigstore staging.

**Steps:**
1. In the CI logs, locate the "Sign GeoRoute Agent Card" and "Sign Data Analysis Agent Card" steps.
2. Verify each step uses `--staging` flag.
3. Verify each step reads the token from `${SIGSTORE_ID_TOKEN}` (not `oidc-token.txt`).

**Expected Result:** Both signing steps complete successfully.

**Pass/Fail:** PASS if both sign steps exit 0.

### TP-4744-04: Verify with Google SA Identity

**Description:** Verify both signed Agent Cards pass verification using the Google SA identity from the conformance token.

**Steps:**
1. In the CI logs, locate the "Verify GeoRoute Agent Card" and "Verify Data Analysis Agent Card" steps.
2. Verify each step uses:
   - `--staging`
   - `--identity "untrusted-sa@sigstore-conformance.iam.gserviceaccount.com"`
   - `--identity_provider "https://accounts.google.com"`

**Expected Result:** Both verification steps pass. Identity matches `untrusted-sa@sigstore-conformance.iam.gserviceaccount.com`.

**Pass/Fail:** PASS if both verify steps exit 0.

### TP-4744-05: CI Stability (No Flakiness)

**Description:** Verify the fix eliminates the intermittent "Current token expires too early" failures.

**Steps:**
1. Trigger the CI pipeline 3 consecutive times (via push, PR update, or `workflow_dispatch`).
2. Check the `sign-agent-card` job result for each run.

**Expected Result:** All 3 runs pass. No "Current token expires too early" errors.

**Pass/Fail:** PASS if 3/3 runs succeed.

### TP-4744-06: No Regression in Other CI Jobs

**Description:** Verify other CI jobs are unaffected by the change.

**Steps:**
1. In the same CI run, check the status of all other jobs:
   - `test` (unit tests)
   - Code Quality (lint)
   - Build (Linux, Windows, macOS)
   - CLI (Linux, Windows, macOS)
   - Python 3.11/3.12/3.13
   - Security (CodeQL, Vulnerability Scan, Dependency Review)

**Expected Result:** All other jobs pass.

**Pass/Fail:** PASS if all non-sign-agent-card jobs pass.

## Regression Tests

- Unit tests (`make test`) pass — 49/49.
- The signed Agent Card artifacts are still uploaded to the workflow run.
- Signed artifacts are verifiable using the Google SA identity constraints.

## Release Gate Criteria

- TP-4744-01 (CI job passes on PR) passes.
- TP-4744-03 and TP-4744-04 (sign and verify with staging) pass.
- TP-4744-05 (stability over 3 runs) passes.
- TP-4744-06 (no regression in other jobs) passes.
