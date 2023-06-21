#!/bin/bash

set -euo pipefail

export TARGET_CHAIN=$1
export FOREIGN_CHAIN=$2
export FOREIGN_EMITTER=$3
export FOREIGN_DOMAIN=$4
export SIGNER_KEY=$5

forge script $(dirname $0)/../forge-scripts/generate_registration_vaa.sol \
    -vv \
    --rpc-url $RPC \
    --private-key $PRIVATE_KEY \
    --broadcast --slow
