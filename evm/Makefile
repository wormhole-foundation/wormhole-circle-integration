include env/testing.env

.PHONY: dependencies test clean all ci

all: build

.PHONY: clean
clean:
	forge clean
	rm -rf node_modules lib out ts/src/ethers-contracts

.PHONY: dependencies
dependencies: node_modules lib/forge-std

node_modules:
	npm ci

lib/forge-std:
	forge install --no-git --no-commit foundry-rs/forge-std

ts/src/ethers-contracts:
	npm run build-types

build: dependencies
	forge build

.PHONY: test
test: dependencies
	forge test --fork-url ${TESTING_FORK_RPC} -vv

.PHONY: ci
ci: dependencies
	forge test --fork-url ${CI_FORK_RPC} -vv --fail-fast

.PHONY: gas-report
gas-report: dependencies
	forge test --fork-url ${TESTING_FORK_RPC} --match-path forge/tests/gas/* --fuzz-runs 512 --gas-report

.PHONY: gas-snapshot
gas-snapshot: dependencies
	forge snapshot --fork-url ${TESTING_FORK_RPC} --diff .gas-snapshot-current
