# Test Plan: SECURESIGN-4743 — client_id Forwarding Fix

## Overview

- **Ticket:** [SECURESIGN-4743](https://redhat.atlassian.net/browse/SECURESIGN-4743)
- **Summary:** `AgentCardSigner` did not forward `client_id`/`client_secret` to `IdentityToken()` or `Issuer.identity_token()`, causing signing to fail with non-default OIDC audiences.
- **Scope:** `sigstore_a2a/signer.py` — three identity acquisition paths (explicit token, ambient credentials, interactive OAuth).
- **Root Cause:** `IdentityToken()` validates the JWT `aud` claim against a `client_id` parameter (default: `"sigstore"`). The signer accepted `client_id` but never passed it through.

## Test Environment

| Resource | Details |
|----------|---------|
| TAS cluster | OpenShift with Securesign CR deployed, Fulcio configured with Keycloak OIDC |
| Keycloak | Client ID `trusted-artifact-signer` (audience differs from default `"sigstore"`) |
| Test user | `jdoe` / `secure` (email: `jdoe@redhat.com`) |
| Python | 3.11+ with `uv` package manager |
| Sigstore staging | For testing with default `"sigstore"` audience |

## Prerequisites

1. TAS cluster is running with Keycloak OIDC issuer
2. TUF trust bootstrapped: `uv run sigstore-a2a trust-instance /tmp/tas-tuf-root.json --instance $TAS_URL`
3. Project dependencies installed: `make install`

## Test Scenarios

### TP-4743-01: Sign with --identity_token and --client_id (Non-Default Audience)

**Description:** Verify that passing `--client_id` alongside `--identity_token` allows signing with a non-default OIDC audience.

**Steps:**
1. Obtain OIDC token from Keycloak (audience = `trusted-artifact-signer`):
   ```bash
   ID_TOKEN=$(curl -sS "$KEYCLOAK_URL/realms/trusted-artifact-signer/protocol/openid-connect/token" \
     -d "grant_type=password&client_id=trusted-artifact-signer&username=jdoe&password=secure&scope=openid email" \
     | python3 -c "import sys,json; print(json.load(sys.stdin)['id_token'])")
   ```
2. Sign with matching `--client_id`:
   ```bash
   uv run sigstore-a2a sign \
     --instance $TAS_URL \
     --identity_token "$ID_TOKEN" \
     --client_id trusted-artifact-signer \
     --output /tmp/signed.json \
     examples/georoute-agent.json
   ```

**Expected Result:** Signing succeeds. Output: `Agent Card signed successfully`.

**Pass/Fail:** PASS if exit code 0 and signed output file created.

### TP-4743-02: Sign with --identity_token Without --client_id (Default Audience)

**Description:** Verify that omitting `--client_id` still works when the token audience matches the default `"sigstore"`.

**Steps:**
1. Obtain an OIDC token with audience `"sigstore"` (e.g., from Sigstore staging or a Keycloak client configured with client ID `"sigstore"`).
2. Sign without `--client_id`:
   ```bash
   uv run sigstore-a2a sign \
     --staging \
     --identity_token "$SIGSTORE_TOKEN" \
     --output /tmp/signed-default.json \
     examples/georoute-agent.json
   ```

**Expected Result:** Signing succeeds (backward compatibility preserved).

**Pass/Fail:** PASS if exit code 0.

### TP-4743-03: Sign with --identity_token and Mismatched --client_id

**Description:** Verify that a mismatched `--client_id` correctly rejects the token.

**Steps:**
1. Obtain OIDC token from Keycloak (audience = `trusted-artifact-signer`).
2. Sign with wrong `--client_id`:
   ```bash
   uv run sigstore-a2a sign \
     --instance $TAS_URL \
     --identity_token "$ID_TOKEN" \
     --client_id wrong-client-id \
     --output /tmp/signed-mismatch.json \
     examples/georoute-agent.json
   ```

**Expected Result:** Signing fails with `Identity token is malformed or missing claims` (audience mismatch).

**Pass/Fail:** PASS if exit code non-zero and error message indicates token validation failure.

### TP-4743-04: Verify Signed Card After client_id Fix

**Description:** Verify that a card signed with `--client_id` can be verified normally.

**Steps:**
1. Sign using TP-4743-01 procedure.
2. Verify:
   ```bash
   uv run sigstore-a2a verify \
     --instance $TAS_URL \
     --identity_provider "$KEYCLOAK_ISSUER" \
     --identity "jdoe@redhat.com" \
     /tmp/signed.json
   ```

**Expected Result:** Verification succeeds. Identity matches `jdoe@redhat.com`.

**Pass/Fail:** PASS if exit code 0 and identity confirmed.

### TP-4743-05: Unit Test Regression

**Description:** Verify all existing unit tests pass after the fix.

**Steps:**
1. Run the full test suite:
   ```bash
   make test
   ```

**Expected Result:** 49/49 tests pass.

**Pass/Fail:** PASS if all tests pass with no failures or errors.

## Regression Tests

- Signing with `--staging` (default audience `"sigstore"`) still works.
- Signing with `--trust_config` still works.
- Signing with `--use_ambient_credentials` in CI (GitHub Actions) still works.
- All existing verify commands with identity constraints still work.

## Release Gate Criteria

- TP-4743-01 (non-default audience signing) passes.
- TP-4743-02 (backward compatibility) passes.
- TP-4743-03 (mismatch rejection) passes.
- TP-4743-04 (verify after fix) passes.
- TP-4743-05 (unit regression) passes — 49/49.
