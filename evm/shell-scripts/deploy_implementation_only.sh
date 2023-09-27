#!/usr/bin/env bash

set -euo pipefail

forge script $(dirname $0)/../forge-scripts/deploy_implementation_only.sol \
    -vv \
    --rpc-url $RPC \
    --broadcast --slow $@