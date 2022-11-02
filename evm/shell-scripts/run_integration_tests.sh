#/bin/bash

pgrep anvil > /dev/null
if [ $? -eq 0 ]; then
    echo "anvil already running"
    exit 1;
fi

anvil \
    -m "myth like bonus scare over problem client lizard pioneer submit female collect" \
    --fork-url $TESTING_FORK_RPC \
	--fork-block-number $TESTING_FORK_BLOCK_NUMBER > anvil.log &

sleep 2

## anvil's rpc
export RPC="http://localhost:8545"

## first key from mnemonic above
export PRIVATE_KEY="0x4f3edf983ac636a65a842ce7c78d9aa706d3b113bce9c46f30d7d21715b23b1d"

export RELEASE_WORMHOLE_ADDRESS=$TESTING_WORMHOLE_ADDRESS
export RELEASE_CIRCLE_BRIDGE_ADDRESS=$TESTING_CIRCLE_BRIDGE_ADDRESS

mkdir -p cache
cp -v foundry.toml cache/foundry.toml
cp -v foundry-test.toml foundry.toml

echo "deploy contracts"
bash $(dirname $0)/deploy_circle_integration.sh > deploy.out 2>&1

echo "overriding foundry.toml"
mv -v cache/foundry.toml foundry.toml

## run tests here
npx ts-mocha -t 1000000 ts/test/*.ts

# nuke
pkill anvil
