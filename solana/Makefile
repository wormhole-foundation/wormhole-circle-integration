SOLANA_CLI="v1.16.16"
ANCHOR_CLI="v0.28.0"

out_mainnet=artifacts-mainnet
out_testnet=artifacts-testnet

.PHONY: all clean check build test lint ci

all: check

check:
	cargo check --all-features

clean:
	anchor clean
	rm -rf node_modules artifacts-mainnet artifacts-testnet ts/tests/artifacts

node_modules:
	npm ci

prune_idl: node_modules ts/scripts/pruneIdlTypes.ts
	cd ts/scripts && npx ts-node pruneIdlTypes.ts

build: $(out_$(NETWORK))
$(out_$(NETWORK)):
ifdef out_$(NETWORK)
	anchor build -p wormhole_circle_integration_solana --arch sbf -- --features "$(NETWORK),no-idl" -- --no-default-features
	mkdir -p $(out_$(NETWORK))
	cp target/deploy/*.so $(out_$(NETWORK))/
endif

test: node_modules
	cargo test --all-features
	anchor build -p wormhole_circle_integration_solana --arch sbf -- --features testnet -- --no-default-features
	mkdir -p ts/tests/artifacts && cp target/deploy/wormhole_circle_integration_solana.so ts/tests/artifacts/testnet_wormhole_circle_integration_solana.so
	solana program dump -u m worm2ZoG2kUd4vFXhvjh93UUH596ayRfgQ2MgjNMTth ts/tests/artifacts/mainnet_core_bridge.so
	anchor build --arch sbf -- --features integration-test -- --no-default-features
	$(MAKE) prune_idl
	anchor test --skip-build

lint:
	cargo fmt --check
	cargo clippy --no-deps --all-targets --all-features -- -D warnings

ci:
	DOCKER_BUILDKIT=1 docker build -f Dockerfile.ci \
		--build-arg SOLANA_CLI=$(SOLANA_CLI) \
		--build-arg ANCHOR_CLI=$(ANCHOR_CLI) \
		.
