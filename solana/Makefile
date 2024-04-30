out_mainnet=artifacts-mainnet
out_testnet=artifacts-testnet

.PHONY: all clean check build test lint ci

all: check

check:
	cargo check --all-features

clean:
	cargo clean
	anchor clean
	rm -rf node_modules artifacts-mainnet artifacts-testnet ts/tests/artifacts

node_modules:
	npm ci

build: $(out_$(NETWORK))
$(out_$(NETWORK)):
ifdef out_$(NETWORK)
	anchor build --no-idl -- --features $(NETWORK)
	mkdir -p $(out_$(NETWORK))
	cp target/deploy/*.so $(out_$(NETWORK))/
endif

test: node_modules ts/tests/artifacts
	anchor build --no-idl -- --features testnet
	cp target/deploy/wormhole_circle_integration_solana.so ts/tests/artifacts/testnet_wormhole_circle_integration_solana.so
	solana program dump -u m worm2ZoG2kUd4vFXhvjh93UUH596ayRfgQ2MgjNMTth ts/tests/artifacts/mainnet_core_bridge.so
	bash sh/run_anchor_test.sh

ts/tests/artifacts:
	mkdir -p ts/tests/artifacts

cargo-test:
	cargo clean && cargo test --all-features

lint:
	cargo fmt --check
	cargo clippy --no-deps --all-targets --all-features -- -D warnings

ci:
	DOCKER_BUILDKIT=1 docker build -f Dockerfile.ci \
		--build-arg SOLANA_CLI=$(SOLANA_CLI) \
		--build-arg ANCHOR_CLI=$(ANCHOR_CLI) \
		.
