# rh-sigstore-a2a

> **Red Hat Tech Preview** — This package is under active development. APIs may change between releases.

A Python library and CLI for keyless signing and verification of
[A2A](https://google.github.io/A2A/) Agent Cards using
[Sigstore](https://sigstore.dev/) with [SLSA](https://slsa.dev/) provenance attestations.

## Features

- **Keyless signing** — no long-lived secrets to manage; signs using short-lived certificates from CI/CD OIDC identity
- **SLSA provenance** — links Agent Cards to their source repository, commit SHA, and build workflow
- **Identity verification** — enforces signer identity, repository, and workflow constraints
- **Private instance support** — works with [Trusted Artifact Signer (TAS)](https://docs.redhat.com/en/documentation/red_hat_trusted_artifact_signer) deployments via `--instance` or `--trust_config`
- **Agent Card serving** — serves signed Agent Cards at A2A well-known endpoints for testing

## Installation

```bash
pip install rh-sigstore-a2a
```

Requires Python 3.11+.

## Quick Start

### Sign an Agent Card

```bash
# In a CI/CD environment with OIDC credentials (e.g., GitHub Actions)
sigstore-a2a sign agent-card.json \
  --output signed-agent-card.json \
  --use_ambient_credentials \
  --provenance \
  --repository owner/repo
```

### Verify a Signed Agent Card

```bash
sigstore-a2a verify signed-agent-card.json \
  --identity_provider https://token.actions.githubusercontent.com \
  --identity "https://github.com/owner/repo/.github/workflows/sign.yml@refs/heads/main" \
  --repository owner/repo
```

### Library Usage

```python
from sigstore_a2a.signer import AgentCardSigner
from sigstore_a2a.verifier import AgentCardVerifier
from sigstore_a2a.provenance import ProvenanceBuilder

# Sign (requires OIDC credentials from CI/CD)
signer = AgentCardSigner(use_ambient_credentials=True)
provenance = ProvenanceBuilder().build_provenance("agent-card.json")
signed_card = signer.sign_agent_card("agent-card.json", provenance_bundle=provenance)

# Verify
verifier = AgentCardVerifier()
result = verifier.verify_signed_card(signed_card)
if result.valid:
    print(f"Valid: signed by {result.identity}")
```

## Trusted Artifact Signer (TAS) Integration

For on-premise deployments using [Red Hat Trusted Artifact Signer](https://docs.redhat.com/en/documentation/red_hat_trusted_artifact_signer),
use `--instance` (TUF-bootstrapped) or `--trust_config` (manual JSON) instead of
the public Sigstore infrastructure.

### Using --instance (TUF-bootstrapped)

```bash
# Bootstrap trust (one-time)
sigstore-a2a trust-instance root.json --instance https://sigstore.example.com

# Sign
sigstore-a2a sign agent-card.json \
  --instance https://sigstore.example.com \
  --use_ambient_credentials \
  --provenance \
  --output signed-agent-card.json

# Verify
sigstore-a2a verify signed-agent-card.json \
  --instance https://sigstore.example.com \
  --identity_provider https://keycloak.example.com/realms/trusted-artifact-signer \
  --identity signer@example.com
```

### Using --trust_config (ClientTrustConfig JSON)

```bash
sigstore-a2a sign agent-card.json \
  --trust_config trust-config.json \
  --identity_token "$OIDC_TOKEN" \
  --client_id my-client \
  --output signed-agent-card.json
```

See [`examples/tas-trust-config.json`](examples/tas-trust-config.json) for a
template. Note that `--staging`, `--instance`, and `--trust_config` are mutually exclusive.

## CLI Reference

```
sigstore-a2a sign <agent-card> [OPTIONS]
  --output, -o PATH       Output path for signed Agent Card
  --staging               Use Sigstore staging environment
  --instance URL          Sigstore instance URL (TUF-bootstrapped)
  --trust_config PATH     Path to ClientTrustConfig JSON
  --use_ambient_credentials  Use ambient CI/CD OIDC credentials
  --identity_token TOKEN  Use a fixed OIDC identity token
  --client_id ID          Custom OIDC client ID
  --provenance            Include SLSA provenance
  --repository REPO       Override repository for provenance
  --commit_sha SHA        Override commit SHA for provenance

sigstore-a2a verify <signed-card> [OPTIONS]
  --staging               Use Sigstore staging environment
  --instance URL          Sigstore instance URL (TUF-bootstrapped)
  --trust_config PATH     Path to ClientTrustConfig JSON
  --identity_provider URL Required OIDC issuer URL
  --identity IDENTITY     Expected signer identity
  --repository REPO       Required repository constraint
  --workflow NAME         Required workflow name constraint

sigstore-a2a trust-instance <root-file> --instance URL
  Bootstrap TUF trust for a private Sigstore instance.

sigstore-a2a serve <signed-card> [OPTIONS]
  --host HOST             Host to bind to (default: 127.0.0.1)
  --port PORT             Port to bind to (default: 8080)
  --staging               Use Sigstore staging environment
  --no-verify             Skip signature verification on startup
```

### Sign Examples

```bash
# Minimal: sign with production trust and interactive auth (local dev)
sigstore-a2a sign agent-card.json

# Write to a specific output path
sigstore-a2a sign agent-card.json --output signed-card.json

# Use Sigstore staging (good for sandbox testing)
sigstore-a2a sign agent-card.json --staging

# Prefer ambient CI credentials (GitHub Actions, etc.)
sigstore-a2a sign agent-card.json --use_ambient_credentials

# Sign with SLSA provenance and repo/commit metadata
sigstore-a2a sign agent-card.json --provenance \
  --repository myorg/myrepo \
  --commit_sha "$GITHUB_SHA" \
  --workflow_ref ".github/workflows/ci.yml@refs/heads/main"

# Private Sigstore instance with provenance and ambient credentials
sigstore-a2a sign agent-card.json \
  --trust_config ./signing_config.json \
  --provenance \
  --use_ambient_credentials
```

### Verify Examples

```bash
# Minimal verification with required identity + identity provider
sigstore-a2a verify signed-card.json \
  --identity dev@example.com \
  --identity_provider https://accounts.google.com

# Enforce GitHub repository + workflow constraints
sigstore-a2a verify signed-card.json \
  --identity "https://github.com/owner/repo/.github/workflows/ci.yml@refs/heads/main" \
  --identity_provider https://token.actions.githubusercontent.com \
  --repository owner/repo \
  --workflow ci

# Use a private trust configuration
sigstore-a2a verify signed-card.json \
  --identity dev@example.com \
  --identity_provider https://accounts.google.com \
  --trust_config ./client-trust-config.json

# Verbose output with certificate and identity details
sigstore-a2a --verbose verify signed-card.json \
  --identity dev@example.com \
  --identity_provider https://accounts.google.com
```

## GitHub Actions Integration

Automated Agent Card signing in GitHub Actions uses OIDC tokens to perform
keyless signing. GitHub generates a token containing metadata about the
repository, workflow, commit SHA, and actor. Sigstore embeds these claims
into a short-lived X.509 certificate, creating an immutable link between
your Agent Card and its source code. Every signature is logged in the
public Rekor transparency log for auditability.

A reference workflow for signing against a private TAS deployment is available at
[`.github/workflows/sign-agentcard-tas.yml`](.github/workflows/sign-agentcard-tas.yml).
See [`examples/README.md`](examples/README.md) for full adaptation instructions.

Below is a minimal workflow for public Sigstore:

```yaml
name: Sign Agent Card
on:
  push:
    branches: [main]

permissions:
  id-token: write   # Required for Sigstore OIDC token
  contents: read

jobs:
  sign-agent-card:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-python@v4
        with:
          python-version: "3.11"

      - name: Install rh-sigstore-a2a
        run: pip install rh-sigstore-a2a

      - name: Sign Agent Card
        run: |
          sigstore-a2a sign agent-card.json \
            --output signed-agent-card.json \
            --use_ambient_credentials \
            --provenance \
            --repository ${{ github.repository }}

      - name: Verify signature
        run: |
          sigstore-a2a verify signed-agent-card.json \
            --identity_provider https://token.actions.githubusercontent.com \
            --identity "https://github.com/${{ github.repository }}/.github/workflows/sign.yml@${{ github.ref }}" \
            --repository ${{ github.repository }}

      - uses: actions/upload-artifact@v4
        with:
          name: signed-agent-card
          path: signed-agent-card.json
          retention-days: 30
```

## Verification and Trust

Agent Card verification checks both signature validity and the identity claims
embedded in the signing certificate. This ties each card back to a specific
repository, workflow, and signer identity.

### Identity Constraints

In production, always enforce identity constraints to ensure the Agent Card
came from a trusted source. Constraints let you specify exactly which OIDC
issuer, signer identity, repository, and workflow you trust:

```bash
# Verify that the card was signed by a specific identity via a known issuer
sigstore-a2a verify signed-agent-card.json \
  --identity_provider https://token.actions.githubusercontent.com \
  --identity "https://github.com/myorg/trusted-repo/.github/workflows/sign.yml@refs/heads/main"

# Add repository and workflow constraints
sigstore-a2a verify signed-agent-card.json \
  --identity_provider https://token.actions.githubusercontent.com \
  --identity "https://github.com/myorg/trusted-repo/.github/workflows/sign.yml@refs/heads/main" \
  --repository myorg/trusted-repo \
  --workflow "Sign Agent Card"
```

Identity constraints defend against several attack scenarios: they prevent an
attacker who has compromised a different repository from producing Agent Cards
that appear to come from your trusted source, and they ensure cards are only
created through approved CI/CD workflows rather than manual processes that
might bypass security controls.

Every signature is automatically logged in the public
[Rekor](https://github.com/sigstore/rekor) transparency log. This creates a
tamper-evident record of when each signature was created, enabling detection of
backdated signatures or other anomalies. The transparency log entry is verified
automatically during `sigstore-a2a verify`.

### Keyless Signing Security

Traditional code signing requires managing long-lived private keys, creating
operational overhead and security risk. Sigstore's keyless signing eliminates
this by using short-lived certificates tied to OIDC identity tokens.

When you sign an Agent Card in GitHub Actions, the process uses an OIDC token
valid only for the duration of your workflow run. This token is exchanged for a
signing certificate that expires within minutes. Benefits:

- **No long-lived secrets** to manage, rotate, or protect
- **Cryptographic binding** to CI/CD identity — forging signatures requires
  compromising the entire development infrastructure
- **Limited exposure** — even if a certificate were compromised, its window of
  misuse is extremely short

### Supply Chain Protection

Agent Cards represent AI agents that will be executed in distributed
environments, making supply chain security critical. The combination of
Sigstore signatures and SLSA provenance creates a verifiable chain of custody
from source code to deployed agent.

When you sign an Agent Card with `--provenance`, the signature embeds metadata
about the exact source code revision, the build environment, and the CI/CD
workflow used. Consumers can verify not just that the signature is valid, but
that the Agent Card came from a trusted repository and was built using an
approved process.

### Verification Best Practices

- **Always use identity constraints** in production. A basic signature check
  only confirms cryptographic validity, not whether you should trust the signer.
- **Require organization-scoped repositories** — enforce that Agent Cards come
  from repositories within your organization using `--repository`.
- **Pin to specific workflows** — use `--workflow` to ensure cards are produced
  only through standardized CI/CD pipelines.
- **Leverage the transparency log** — in high-security environments, use
  [rekor-cli](https://github.com/sigstore/rekor) for direct transparency log
  queries and anomaly detection.

### Operational Security

- Ensure your GitHub repository has appropriate **branch protection rules** and
  required status checks. Signature security is only as strong as your
  development environment.
- Consider **environment-specific signing**: Agent Cards intended for production
  should only be signed from protected branches, while development versions can
  be signed from feature branches. Implement this using different `--repository`
  and `--workflow` constraints in your verification policies.

## API Reference

### AgentCardSigner

```python
class AgentCardSigner:
    def __init__(
        self,
        identity_token: str | None = None,
        trust_config: Path | None = None,
        staging: bool = False,
        instance: str | None = None,
        client_id: str | None = None,
        client_secret: str | None = None,
        use_ambient_credentials: bool = False,
        verbose: bool = False,
    )

    def sign_agent_card(
        self,
        agent_card: AgentCard | dict | str | Path,
        provenance_bundle: SLSAProvenance | None = None,
    ) -> SignedAgentCard

    def sign_file(
        self,
        input_path: str | Path,
        output_path: str | Path | None = None,
        provenance_bundle: SLSAProvenance | None = None,
    ) -> Path
```

**Parameters:**
- `identity_token` — Pre-obtained OIDC token (takes priority over ambient credentials)
- `trust_config` — Path to ClientTrustConfig JSON (mutually exclusive with `staging`/`instance`)
- `staging` — Use Sigstore staging environment
- `instance` — Sigstore instance URL (TUF-bootstrapped, mutually exclusive with `staging`/`trust_config`)
- `use_ambient_credentials` — Detect and use CI/CD OIDC credentials automatically

### AgentCardVerifier

```python
class AgentCardVerifier:
    def __init__(
        self,
        identity: str | None = None,
        oidc_issuer: str | None = None,
        staging: bool = False,
        trust_config: Path | None = None,
        instance: str | None = None,
    )

    def verify_signed_card(
        self,
        signed_card: SignedAgentCard | dict | str | Path,
        constraints: IdentityConstraints | None = None,
    ) -> VerificationResult

    def verify_file(
        self,
        file_path: str | Path,
        constraints: IdentityConstraints | None = None,
    ) -> VerificationResult
```

**Parameters:**
- `identity` — Expected signer identity (email or URI)
- `oidc_issuer` — Expected OIDC issuer URL
- `staging` — Use Sigstore staging environment
- `trust_config` — Path to ClientTrustConfig JSON
- `instance` — Sigstore instance URL (TUF-bootstrapped)

### IdentityConstraints

```python
class IdentityConstraints:
    def __init__(
        self,
        repository: str | None = None,     # e.g., "owner/repo"
        workflow: str | None = None,        # e.g., "Sign Agent Card"
        identity: str | None = None,        # e.g., "dev@example.com"
        identity_provider: str | None = None,  # e.g., "https://accounts.google.com"
    )
```

### VerificationResult

```python
class VerificationResult:
    valid: bool                              # Whether verification succeeded
    agent_card: AgentCard | None             # Verified agent card (extracted from DSSE payload)
    certificate: x509.Certificate | None     # Signing certificate
    identity: dict[str, Any]                 # Extracted identity claims
    errors: list[str]                        # Verification errors (if any)
```

**VerificationResult fields:**
- `valid`: Whether verification succeeded
- `agent_card`: Verified AgentCard (protobuf message, extracted from DSSE payload)
- `raw_card_data`: Raw predicate dict from the DSSE payload, preserving fields that may not map to the current protobuf schema (e.g., `url` from v0.2.x cards)
- `certificate`: Signing certificate
- `identity`: Extracted identity information
- `errors`: List of verification errors

### ProvenanceBuilder

```python
class ProvenanceBuilder:
    def __init__(self, build_type: str = "https://github.com/actions/workflow@v1")

    def build_provenance(
        self,
        agent_card: AgentCard | dict | str | Path,
        source_repo: str | None = None,
        commit_sha: str | None = None,
        workflow_ref: str | None = None,
        builder_id: str | None = None,
        external_params: dict | None = None,
    ) -> SLSAProvenance

    def create_subject(
        self,
        agent_card: AgentCard | dict | str | Path,
        name: str | None = None,
    ) -> ProvenanceSubject
```

## Related Projects

- [Sigstore](https://sigstore.dev/) — Keyless signing infrastructure
- [sigstore-python](https://github.com/sigstore/sigstore-python) — Python client for Sigstore (used by this library)
- [SLSA](https://slsa.dev/) — Supply chain security framework
- [A2A Protocol](https://google.github.io/A2A/) — Agent-to-Agent communication specification
- [Red Hat Trusted Artifact Signer](https://docs.redhat.com/en/documentation/red_hat_trusted_artifact_signer) — On-premise Sigstore deployment for enterprise environments
- [Rekor](https://github.com/sigstore/rekor) — Transparency log for Sigstore signatures
- [Fulcio](https://github.com/sigstore/fulcio) — Certificate authority for keyless signing

## License

Apache License 2.0

## Links

- [PyPI Package](https://pypi.org/project/rh-sigstore-a2a/)
- [Source Code](https://github.com/securesign/sigstore-a2a)
- [Issue Tracker](https://github.com/securesign/sigstore-a2a/issues)
