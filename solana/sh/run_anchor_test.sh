#!/bin/bash

### I really hope this is just a temporary script. We cannot specify clone-upgradable-programs in
### Anchor.toml, so we need to clone the upgradeable programs manually.

if test -f .validator_pid; then
    echo "Killing existing validator"
    kill $(cat .validator_pid)
    rm .validator_pid
fi

rm -rf .anchor/test-ledger
mkdir -p .anchor

anchor build -- --features integration-test

### Start up the validator.
echo "Starting solana-test-validator"

solana-test-validator \
    --ledger \
    .anchor/test-ledger \
    --mint \
    pFCBP4bhqdSsrWUVTgqhPsLrfEdChBK17vgFM7TxjxQ \
    --bpf-program \
    Wormho1eCirc1e1ntegration111111111111111111 \
    target/deploy/wormhole_circle_integration_solana.so \
    --bpf-program \
    worm2ZoG2kUd4vFXhvjh93UUH596ayRfgQ2MgjNMTth \
    ts/tests/artifacts/mainnet_core_bridge.so \
    --account \
    4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU \
    ts/tests/accounts/usdc_mint.json \
    --account \
    6s9vuDVXZsJY1Qp29cFxKgbSmpTH2QWnrjZzPHWmFXCz \
    ts/tests/accounts/usdc_payer_token.json \
    --account \
    Afgq3BHEfCE7d78D2XE9Bfyu2ieDqvE24xX8KDwreBms \
    ts/tests/accounts/token_messenger_minter/token_messenger.json \
    --account \
    DBD8hAwLDRQkTsu6EqviaYNGKPnsAMmQonxf7AH8ZcFY \
    ts/tests/accounts/token_messenger_minter/token_minter.json \
    --account \
    AEfKU8wHGtYgsXpymQ6e1cGHJJeKqCj95pw82iyRUKEs \
    ts/tests/accounts/token_messenger_minter/usdc_custody_token.json \
    --account \
    4xt9P42CcMHXAgvemTnzineHp6owfGUcrg1xD9V7mdk1 \
    ts/tests/accounts/token_messenger_minter/usdc_local_token.json \
    --account \
    ADcG1d7znq6wR73BJgEh7dR4vTJcETLLyfXMNZjJVwk4 \
    ts/tests/accounts/token_messenger_minter/usdc_token_pair.json \
    --account \
    Hazwi3jFQtLKc2ughi7HFXPkpDeso7DQaMR9Ks4afh3j \
    ts/tests/accounts/token_messenger_minter/ethereum_remote_token_messenger.json \
    --account \
    BWyFzH6LsnmDAaDWbGsriQ9SiiKq1CF6pbH4Ye3kzSBV \
    ts/tests/accounts/token_messenger_minter/misconfigured_remote_token_messenger.json \
    --account \
    BWrwSWjbikT3H7qHAkUEbLmwDQoB4ZDJ4wcSEhSPTZCu \
    ts/tests/accounts/message_transmitter/message_transmitter_config.json \
    --account \
    6bi4JGDoRwUs9TYBuvoA7dUVyikTJDrJsJU1ew6KVLiu \
    ts/tests/accounts/core_bridge_testnet/config.json \
    --account \
    7s3a1ycs16d6SNDumaRtjcoyMaTDZPavzgsmS3uUZYWX \
    ts/tests/accounts/core_bridge_testnet/fee_collector.json \
    --account \
    dxZtypiKT5D9LYzdPxjvSZER9MgYfeRVU5qpMTMTRs4 \
    ts/tests/accounts/core_bridge_testnet/guardian_set_0.json \
    --account \
    2yVjuQwpsvdsrywzsJJVs9Ueh4zayyo5DYJbBNc3DDpn \
    ts/tests/accounts/core_bridge_mainnet/config.json \
    --account \
    9bFNrXNb2WTx8fMHXCheaZqkLZ3YCCaiqTftHxeintHy \
    ts/tests/accounts/core_bridge_mainnet/fee_collector.json \
    --account \
    DS7qfSAgYsonPpKoAjcGhX9VFjXdGkiHjEDkTidf8H2P \
    ts/tests/accounts/core_bridge_mainnet/guardian_set_0.json \
    --bind-address \
    0.0.0.0 \
    --clone-upgradeable-program \
    3u8hJUVTA4jH1wYAyUur7FFZVQ8H635K3tSHHF4ssjQ5 \
    --clone \
    Es2E4JZuFwA5gcCs1ubmAegekraPnUxFNpxHfWfWFcqk \
    --clone \
    4tTfYz2SqRcZWqyBk1yHyEPzHjoHNbUErQbifBkLmzbT \
    --clone-upgradeable-program \
    CCTPmbSD7gX1bxKPAmg77w8oFzNFpaQiQUWD43TKaecd \
    --clone \
    AqT6GNqtiEpTjYhAeTwA1orjryPiFFTZ9REGqE93gpnx \
    --clone \
    7bu9ccL3uu9xNCLE4ZuUX43sg7HUfort8YyLxcq6G9cQ \
    --clone-upgradeable-program \
    wcihrWf1s91vfukW7LW8ZvR1rzpeZ9BrtZ8oyPkWK5d \
    --clone \
    7hs2RmXGHyLdNPDeB2yfWXEbKqJ2dyv6LGHERAArEUpy \
    --clone-upgradeable-program \
    CCTPiPYPc6AsJuwueEnWgSgucamXDZwBd53dQ11YiKX3 \
    --rpc-port \
    8899 \
    --ticks-per-slot \
    16 \
    --url \
    https://api.devnet.solana.com \
    > /dev/null 2>&1 &

echo $! > .validator_pid

### Start up wait.
sleep 10

### Run the tests.
anchor test --skip-build --skip-local-validator --skip-deploy

EXIT_CODE=$?

### Finally kill the validator.
kill $(cat .validator_pid)
rm .validator_pid

exit $EXIT_CODE
