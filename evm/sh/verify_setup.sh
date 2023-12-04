#/usr/bin/env bash

etherscan_key=$1

forge verify-contract --chain-id $RELEASE_EVM_CHAIN_ID --watch \
    --compiler-version v0.8.19 $CIRCLE_INTEGRATION_SETUP \
    src/CircleIntegration/CircleIntegrationSetup.sol:CircleIntegrationSetup \
    --etherscan-api-key $etherscan_key
