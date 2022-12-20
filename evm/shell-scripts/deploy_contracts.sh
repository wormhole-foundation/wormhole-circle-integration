#!/bin/bash

forge script $(dirname $0)/../forge-scripts/deploy_contracts.sol \
    --rpc-url $RPC \
    --private-key $PRIVATE_KEY \
    --broadcast --slow