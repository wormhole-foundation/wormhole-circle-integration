#!/bin/bash

set -euo pipefail

forge script $(dirname $0)/../forge-scripts/generate_registration_vaa.sol \
    -vv \
    --rpc-url $RPC \
    --private-key $PRIVATE_KEY \
    --broadcast --slow
