#/usr/bin/env bash

etherscan_key=$1

governance_chain_id=1
governance_contract=0x0000000000000000000000000000000000000000000000000000000000000004

setup_bytes=$(cast calldata "function setup(address,address,uint8,address,uint16,bytes32)" $CIRCLE_INTEGRATION_IMPLEMENTATION $RELEASE_WORMHOLE_ADDRESS $RELEASE_WORMHOLE_FINALITY $RELEASE_CIRCLE_BRIDGE_ADDRESS $governance_chain_id $governance_contract)

forge verify-contract --chain-id $RELEASE_EVM_CHAIN_ID --watch \
    --constructor-args $(cast abi-encode "constructor(address,bytes)" $CIRCLE_INTEGRATION_SETUP $setup_bytes) \
    --compiler-version v0.8.19 $CIRCLE_INTEGRATION_PROXY \
    src/circle_integration/CircleIntegrationProxy.sol:CircleIntegrationProxy \
    --etherscan-api-key $etherscan_key
