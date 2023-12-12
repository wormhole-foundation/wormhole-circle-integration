#!/usr/bin/env bash

forge script $(dirname $0)/../forge-scripts/deploy_contracts.sol \
    --rpc-url $CONFIGURE_CCTP_RPC \
    --broadcast --slow $@