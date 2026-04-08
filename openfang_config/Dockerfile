FROM debian:bookworm-slim

ARG TARGETARCH
ARG OPENFANG_VERSION=v0.5.6
ARG OPENFANG_SHA256_AMD64
ARG OPENFANG_SHA256_ARM64

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    wget \
    socat \
    python3 \
    python3-cryptography \
    && rm -rf /var/lib/apt/lists/*

# Fake gcloud wrapper — generates OAuth2 tokens from the service account key file
# without requiring the full (~300 MB) Google Cloud SDK.
COPY gcp-token.py /usr/local/bin/gcp-token.py
COPY fake-gcloud.sh /usr/local/bin/gcloud
RUN chmod +x /usr/local/bin/gcp-token.py /usr/local/bin/gcloud

RUN case "$TARGETARCH" in \
      amd64) ARCH="x86_64"; EXPECTED_SHA256="$OPENFANG_SHA256_AMD64" ;; \
      arm64) ARCH="aarch64"; EXPECTED_SHA256="$OPENFANG_SHA256_ARM64" ;; \
      *) echo "Unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac && \
    test -n "$EXPECTED_SHA256" || { echo "Missing SHA-256 for $TARGETARCH build" >&2; exit 1; } && \
    wget -qO /tmp/openfang.tar.gz \
      "https://github.com/RightNow-AI/openfang/releases/download/${OPENFANG_VERSION}/openfang-${ARCH}-unknown-linux-gnu.tar.gz" && \
    echo "${EXPECTED_SHA256}  /tmp/openfang.tar.gz" | sha256sum -c - && \
    mkdir /tmp/of && \
    tar xzf /tmp/openfang.tar.gz -C /tmp/of && \
    find /tmp/of -name openfang -type f | head -1 | xargs -I{} cp {} /usr/local/bin/openfang && \
    chmod +x /usr/local/bin/openfang && \
    rm -rf /tmp/openfang.tar.gz /tmp/of

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 50051
VOLUME /data
ENV OPENFANG_HOME=/data
ENTRYPOINT ["/entrypoint.sh"]
