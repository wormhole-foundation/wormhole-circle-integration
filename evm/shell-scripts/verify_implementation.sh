#/usr/bin/env bash

etherscan_key=$1

forge verify-contract --chain-id $RELEASE_EVM_CHAIN_ID --watch \
    --compiler-version v0.8.19 $CIRCLE_INTEGRATION_IMPLEMENTATION \
    src/circle_integration/CircleIntegrationImplementation.sol:CircleIntegrationImplementation \
    --etherscan-api-key $etherscan_key
