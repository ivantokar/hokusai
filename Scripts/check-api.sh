#!/bin/sh
# Lists public API changes of the Hokusai product against a git ref, using
# swift-api-digester. Run before a release and review every reported break.
#
#   Scripts/check-api.sh 1.5.0        # against a tag
#   Scripts/check-api.sh origin/main  # against a branch
set -eu
baseline="${1:?usage: Scripts/check-api.sh <git-ref>}"
exec swift package diagnose-api-breaking-changes "$baseline" --products Hokusai
