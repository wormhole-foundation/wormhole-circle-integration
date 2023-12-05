include env/testing.env

.PHONY: dependencies unit-test forge-test integration-test clean all

all: build

.PHONY: clean
clean:
	rm -rf anvil.log node_modules lib out ts/src/ethers-contracts

.PHONY: dependencies
dependencies: node_modules lib/forge-std lib/wormhole

node_modules:
	yarn

lib/forge-std:
	forge install --no-git --no-commit foundry-rs/forge-std

lib/wormhole:
	forge install --no-git --no-commit wormhole=wormhole-foundation/wormhole

build: dependencies
	forge build
	yarn build-types

.PHONY: unit-test
unit-test: forge-test

.PHONY: forge-test
forge-test: dependencies
	forge test \
		-vv \
		--fork-url ${TESTING_FORK_RPC} \

.PHONY: forge-test
gas-report: dependencies
	forge test \
		--fork-url ${TESTING_FORK_RPC} \
		--gas-report

.PHONY: integration-test
integration-test: dependencies build
	bash shell-scripts/run_integration_tests.sh

.PHONY: test
test: forge-test integration-test

