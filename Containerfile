FROM python:3.13-slim AS builder

WORKDIR /app
COPY sigstore_a2a /app/sigstore_a2a
COPY pyproject.toml /app/
COPY README.md /app/
COPY LICENSE /app/
RUN pip install --no-cache-dir .

FROM python:3.13-slim

COPY --from=builder /usr/local/bin/sigstore-a2a /usr/local/bin/
COPY --from=builder /usr/local/lib/python3.13/site-packages /usr/local/lib/python3.13/site-packages
COPY LICENSE /licenses/license.txt

USER 65532:65532

ENTRYPOINT ["sigstore-a2a"]
CMD ["--help"]

LABEL org.opencontainers.image.source="https://github.com/securesign/sigstore-a2a"
LABEL org.opencontainers.image.description="rh-sigstore-a2a: Sigstore keyless signing for A2A Agent Cards"
LABEL org.opencontainers.image.licenses="Apache-2.0"
