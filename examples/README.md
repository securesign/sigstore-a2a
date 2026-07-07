# Example Agent Cards

This directory contains example A2A Agent Card JSON files for testing and demonstration.

## Unsigned Agent Cards

- `georoute-agent.json` - GeoSpatial Route Planner Agent
- `data-analysis-agent.json` - Data Analysis Agent

## Signed Agent Cards (Staging)

Pre-signed examples using Sigstore **staging** environment with the [sigstore-conformance testing token](https://storage.googleapis.com/sigstore-conformance-testing-token/untrusted-testing-token.txt) identity.

- `signed-georoute-agent.json`
- `signed-data-analysis-agent.json`

### Verifying

```bash
sigstore-a2a verify examples/signed-georoute-agent.json \
  --staging \
  --identity_provider https://accounts.google.com \
  --identity "untrusted-sa@sigstore-conformance.iam.gserviceaccount.com"
```

## Usage

### Signing

```bash
sigstore-a2a sign examples/georoute-agent.json --output signed.json
```

### Verifying

```bash
sigstore-a2a verify signed.json --identity_provider <issuer> --identity <identity>
```

## Trusted Artifact Signer (TAS) Reference Workflow

The `.github/workflows/sign-agentcard-tas.yml` workflow demonstrates end-to-end
Agent Card signing against a private TAS deployment instead of public Sigstore.
This is the canonical example for Platform Engineers integrating keyless provenance
into enterprise CI/CD pipelines.

### What the workflow does

1. **Bootstrap trust** — downloads TUF metadata from your TAS instance via the
   `trust-instance` command
2. **Sign** — signs an Agent Card using `--instance` with GitHub Actions OIDC
   identity (`id-token: write`), with optional SLSA provenance via `--provenance`
3. **Verify** — verifies the signed Agent Card against the same TAS instance

### How to adapt it

1. Replace the `TAS_URL` and `TAS_TUF_ROOT` environment variables in the workflow
   with your TAS deployment URL and the path to your TUF root metadata file.
2. Alternatively, use `--trust_config` with a `ClientTrustConfig` JSON file
   instead of `--instance`. See `examples/tas-trust-config.json` for a template.
3. Ensure your GitHub Actions environment has `id-token: write` permissions
   for OIDC keyless signing.

### Example ClientTrustConfig

`tas-trust-config.json` is a template `ClientTrustConfig` with placeholder URLs.
Replace all `<BASE64-ENCODED-*>` values and `*.tas.example.com` URLs with your
TAS deployment's actual certificates and endpoints. For details on the
`ClientTrustConfig` format, see the
[Sigstore protobuf specification](https://github.com/sigstore/protobuf-specs).

### Signing with --trust_config

```bash
sigstore-a2a sign examples/georoute-agent.json \
  --trust_config examples/tas-trust-config.json \
  --use_ambient_credentials \
  --provenance \
  --output signed.json
```

### Signing with --instance (TUF-bootstrapped)

```bash
# Bootstrap trust first
sigstore-a2a trust-instance root.json --instance https://sigstore.example.com

# Then sign
sigstore-a2a sign examples/georoute-agent.json \
  --instance https://sigstore.example.com \
  --use_ambient_credentials \
  --provenance \
  --output signed.json
```

### Verifying against TAS

```bash
# Verify with --instance (after trust-instance bootstrap)
sigstore-a2a verify signed.json \
  --instance https://sigstore.example.com \
  --identity_provider https://token.actions.githubusercontent.com \
  --identity "https://github.com/owner/repo/.github/workflows/sign-agentcard-tas.yml@refs/heads/main" \
  --repository owner/repo

# Verify with --trust_config
sigstore-a2a verify signed.json \
  --trust_config examples/tas-trust-config.json \
  --identity_provider https://token.actions.githubusercontent.com \
  --identity "https://github.com/owner/repo/.github/workflows/sign-agentcard-tas.yml@refs/heads/main" \
  --repository owner/repo
```

Note: `--staging`, `--instance`, and `--trust_config` are mutually exclusive.

## CI/CD

These agent cards are automatically signed and verified in CI using production Sigstore.
