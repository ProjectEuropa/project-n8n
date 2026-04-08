#!/bin/sh
# Minimal gcloud stub — handles only the one command OpenFang calls.
# All other subcommands are unsupported and will return an error.
if [ "$1" = "auth" ] && [ "$2" = "application-default" ] && [ "$3" = "print-access-token" ]; then
    exec python3 /usr/local/bin/gcp-token.py
else
    echo "gcloud stub: unsupported command: $*" >&2
    exit 1
fi
