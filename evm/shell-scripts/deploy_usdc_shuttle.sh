#!/bin/bash

RPC=$1

forge script forge-scripts/deploy_contracts.sol \
    --rpc-url $RPC \
    --private-key $PRIVATE_KEY \
    --broadcast --slow