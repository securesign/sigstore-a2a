# Test Plan: SECURESIGN-4631 — TAS Reference Workflow

## Overview

- **Ticket:** [SECURESIGN-4631](https://redhat.atlassian.net/browse/SECURESIGN-4631)
- **Summary:** Reference GitHub Actions workflow for signing A2A Agent Cards against a private TAS deployment using OIDC keyless identity.
- **Scope:** Workflow YAML, ClientTrustConfig JSON template, examples README documentation.
- **Deliverables under test:**
  - `.github/workflows/sign-agentcard-tas.yml`
  - `examples/tas-trust-config.json`
  - `examples/README.md` (TAS section)

## Test Environment

| Resource | Details |
|----------|---------|
| TAS cluster | OpenShift with Securesign CR deployed (Fulcio, Rekor, TUF, TSA) |
| Keycloak | OIDC issuer configured in Fulcio with client ID `trusted-artifact-signer` |
| Test user | `jdoe` / `secure` (email: `jdoe@redhat.com`) in Keycloak realm `trusted-artifact-signer` |
| GitHub Actions | Repository with `workflow_dispatch` permissions and `id-token: write` |
| Python | 3.11+ with `uv` package manager |

## Prerequisites

1. TAS cluster is running and Securesign CR status is `Ready`
2. TUF root metadata downloaded: `curl -o /tmp/tas-tuf-root.json <TUF_URL>/root.json`
3. Project dependencies installed: `make install`
4. Keycloak user credentials available for OIDC token acquisition

## Test Scenarios

### TP-4631-01: Workflow YAML Syntax Validation

**Description:** Verify the workflow file is syntactically valid YAML and conforms to GitHub Actions schema.

**Steps:**
1. Parse the workflow file with a YAML parser:
   ```bash
   python3 -c "import yaml; yaml.safe_load(open('.github/workflows/sign-agentcard-tas.yml')); print('PASS')"
   ```
2. Verify required top-level keys exist: `name`, `on`, `permissions`, `jobs`.
3. Verify `permissions` includes `id-token: write` and `contents: read`.

**Expected Result:** YAML parses without error. All required keys present. Permissions correctly scoped.

**Pass/Fail:** PASS if no parse errors and all keys present.

### TP-4631-02: ClientTrustConfig JSON Schema Validation

**Description:** Verify the example trust config is valid JSON that conforms to the Sigstore ClientTrustConfig v0.1 schema.

**Steps:**
1. Validate JSON syntax:
   ```bash
   python3 -c "import json; json.load(open('examples/tas-trust-config.json')); print('PASS')"
   ```
2. Validate schema by replacing placeholders and parsing with sigstore library:
   ```python
   import re
   from sigstore.models import ClientTrustConfig
   raw = open('examples/tas-trust-config.json').read()
   raw = re.sub(r'<BASE64-ENCODED-[^>]+>', 'dGVzdA==', raw)
   ClientTrustConfig.from_json(raw)
   ```
3. Verify all Service objects in `signingConfig` contain the required `operator` field.
4. Verify placeholder URLs use `*.tas.example.com` (IANA-reserved, safe to commit).

**Expected Result:** JSON is valid. `ClientTrustConfig.from_json()` succeeds after placeholder replacement. All Service objects have `operator`.

**Pass/Fail:** PASS if parsing succeeds and all fields present.

### TP-4631-03: Trust Bootstrap Against Live TAS

**Description:** Bootstrap TUF trust for the TAS instance using the `trust-instance` CLI command.

**Steps:**
1. Download TUF root: `curl -o /tmp/tas-tuf-root.json $TUF_URL/root.json`
2. Bootstrap trust:
   ```bash
   uv run sigstore-a2a trust-instance /tmp/tas-tuf-root.json --instance $TAS_URL
   ```

**Expected Result:** Output includes `Trust bootstrapped for <TAS_URL>`.

**Pass/Fail:** PASS if command exits 0 and prints success message.

### TP-4631-04: Sign Agent Card Against TAS

**Description:** Sign an Agent Card using a Keycloak OIDC token against the TAS instance.

**Steps:**
1. Obtain OIDC token from Keycloak:
   ```bash
   ID_TOKEN=$(curl -sS "$KEYCLOAK_URL/realms/trusted-artifact-signer/protocol/openid-connect/token" \
     -d "grant_type=password&client_id=trusted-artifact-signer&username=jdoe&password=secure&scope=openid email" \
     | python3 -c "import sys,json; print(json.load(sys.stdin)['id_token'])")
   ```
2. Sign the agent card:
   ```bash
   uv run sigstore-a2a sign \
     --instance $TAS_URL \
     --identity_token "$ID_TOKEN" \
     --client_id trusted-artifact-signer \
     --provenance \
     --output /tmp/signed-agent-card.json \
     examples/georoute-agent.json
   ```

**Expected Result:** Output includes `Agent Card signed successfully`. Signed card written to output path.

**Pass/Fail:** PASS if command exits 0 and output file exists with valid JSON containing `attestations`.

### TP-4631-05: Verify Signed Agent Card (Positive)

**Description:** Verify the signed Agent Card with correct identity constraints.

**Steps:**
1. Run verification:
   ```bash
   uv run sigstore-a2a --verbose verify \
     --instance $TAS_URL \
     --identity_provider "$KEYCLOAK_ISSUER" \
     --identity "jdoe@redhat.com" \
     /tmp/signed-agent-card.json
   ```

**Expected Result:** Output includes `Agent Card signature is valid`. Signing identity shows `jdoe@redhat.com`.

**Pass/Fail:** PASS if command exits 0 and identity matches.

### TP-4631-06: Verify Signed Agent Card (Negative — Wrong Identity)

**Description:** Verify that a wrong identity is correctly rejected.

**Steps:**
1. Run verification with wrong identity:
   ```bash
   uv run sigstore-a2a verify \
     --instance $TAS_URL \
     --identity_provider "$KEYCLOAK_ISSUER" \
     --identity "attacker@evil.com" \
     /tmp/signed-agent-card.json
   ```

**Expected Result:** Output includes `Certificate's SANs do not match attacker@evil.com`. Command exits with non-zero code.

**Pass/Fail:** PASS if command exits non-zero and error message confirms SAN mismatch.

### TP-4631-07: README Documentation Accuracy

**Description:** Verify that all CLI examples in the TAS section of `examples/README.md` reference correct flags.

**Steps:**
1. Extract all CLI commands from the TAS section of `examples/README.md`.
2. Cross-reference each flag against `sigstore_a2a/cli/main.py`:
   - `--instance`, `--trust_config`, `--use_ambient_credentials`, `--provenance`, `--output` (sign)
   - `--instance`, `--trust_config`, `--identity_provider`, `--identity`, `--repository` (verify)
   - `trust-instance ROOT_FILE --instance URL` (trust-instance)
3. Verify mutual exclusivity note for `--staging`/`--instance`/`--trust_config` is present.
4. Verify verify examples include `--repository`.

**Expected Result:** All flags match CLI definitions. Mutual exclusivity documented. Verify examples include `--repository`.

**Pass/Fail:** PASS if all flags are correct and documentation is complete.

### TP-4631-08: Workflow Dispatch with Custom Input

**Description:** Verify the workflow accepts a custom `agent_card` input path.

**Steps:**
1. Trigger workflow via GitHub Actions UI with `agent_card` set to `examples/data-analysis-agent.json`.
2. Monitor workflow execution.

**Expected Result:** Workflow signs and verifies the specified agent card (not the default).

**Pass/Fail:** PASS if workflow completes successfully with the custom input.

## Regression Tests

- Existing `ci.yml` sign-agent-card job continues to pass (staging signing unaffected).
- Existing unit tests (`make test`) all pass (49/49).
- Existing signed examples in `examples/` remain verifiable.

## Release Gate Criteria

- All test scenarios TP-4631-01 through TP-4631-07 pass.
- TP-4631-08 passes when GitHub Actions environment is available.
- No regression in existing CI pipeline.
