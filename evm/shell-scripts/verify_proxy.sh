#/bin/bash

chain_id=$1
deployed_addr=$2
optimizer_runs=$3
etherscan_key=$4
setup_addr=$5
setup_bytes=$6

echo $chain_id $deployed_addr $optimizer_runs $etherscan_key

forge verify-contract --chain-id $chain_id --num-of-optimizations $optimizer_runs --watch \
    --constructor-args $(cast abi-encode "constructor(address,bytes)" $setup_addr $setup_bytes) \
    --compiler-version v0.8.19 $deployed_addr \
    src/circle_integration/CircleIntegrationProxy.sol:CircleIntegrationProxy \
    --etherscan-api-key $etherscan_key
