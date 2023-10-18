#!/usr/bin/env bash

# Usage: ./submit_testnet_registration <target chain> <foreign chain> <foreign emitter> <foreign domain> <forge script args (keys)>

set -euo pipefail

export TARGET_CHAIN=$1
export FOREIGN_CHAIN=$2
export FOREIGN_EMITTER=$3
export FOREIGN_DOMAIN=$4
export SIGNER_KEY=$5

shift 5 # <- remove 5 first arguments

forge script $(dirname $0)/../forge-scripts/submit_testnet_registration.sol \
    -vv \
    --rpc-url $CONFIGURE_CCTP_RPC \
    --broadcast --slow $@
