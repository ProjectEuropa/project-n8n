#!/bin/sh
# OpenFang は 127.0.0.1:50051 にバインドするため、
# socat で 0.0.0.0:8080 → 127.0.0.1:50051 に転送する（外部アクセス用）
socat TCP-LISTEN:8080,fork,reuseaddr TCP:127.0.0.1:50051 &
exec openfang start --config /data/config.toml
