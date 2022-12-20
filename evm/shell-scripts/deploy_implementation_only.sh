#!/bin/bash

set -euo pipefail

forge script $(dirname $0)/../forge-scripts/deploy_implementation_only.sol \
    -vv \
    --rpc-url $RPC \
    --private-key $PRIVATE_KEY \
    --broadcast --slow