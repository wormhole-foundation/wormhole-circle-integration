#/bin/bash

pgrep anvil > /dev/null
if [ $? -eq 0 ]; then
    echo "anvil already running"
    exit 1;
fi

# ethereum goerli testnet
anvil \
    -m "myth like bonus scare over problem client lizard pioneer submit female collect" \
    --port 8545 \
    --fork-url $ETH_FORK_RPC > anvil_eth.log &

# avalanche fuji testnet
anvil \
    -m "myth like bonus scare over problem client lizard pioneer submit female collect" \
    --port 8546 \
    --fork-url $AVAX_FORK_RPC > anvil_avax.log &

sleep 2

## first key from mnemonic above
export PRIVATE_KEY="0x4f3edf983ac636a65a842ce7c78d9aa706d3b113bce9c46f30d7d21715b23b1d"

mkdir -p cache
cp -v foundry.toml cache/foundry.toml
cp -v foundry-test.toml foundry.toml

echo "deploy contracts"
RELEASE_WORMHOLE_ADDRESS=$ETH_WORMHOLE_ADDRESS \
RELEASE_CIRCLE_BRIDGE_ADDRESS=$ETH_CIRCLE_BRIDGE_ADDRESS \
forge script forge-scripts/deploy_contracts.sol \
    --rpc-url http://localhost:8545 \
    --private-key $PRIVATE_KEY \
    --broadcast --slow > deploy.out 2>&1

RELEASE_WORMHOLE_ADDRESS=$AVAX_WORMHOLE_ADDRESS \
RELEASE_CIRCLE_BRIDGE_ADDRESS=$AVAX_CIRCLE_BRIDGE_ADDRESS \
forge script forge-scripts/deploy_contracts.sol \
    --rpc-url http://localhost:8546 \
    --private-key $PRIVATE_KEY \
    --broadcast --slow >> deploy.out 2>&1

forge script forge-scripts/deploy_mock_contracts.sol \
    --rpc-url http://localhost:8546 \
    --private-key $PRIVATE_KEY \
    --broadcast --slow >> deploy.out 2>&1

echo "overriding foundry.toml"
mv -v cache/foundry.toml foundry.toml

## run tests here
npx ts-mocha -t 1000000 ts/test/*.ts

# nuke
pkill anvil
