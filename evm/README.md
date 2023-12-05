# EVM Wormhole-Circle-Integration

## Prerequisites

Install [Foundry tools](https://book.getfoundry.sh/getting-started/installation), which include `forge`, `anvil` and `cast` CLI tools.

## Build

Run the following commands to install necessary dependencies and to build the smart contracts:

```
make dependencies
make build
```

## Deployment

To deploy Wormhole's Circle Integration contracts, see the [Wormhole Book](https://book.wormhole.com/reference/contracts.html) to fetch the Wormhole Core contract address of the target network. Next, create a `.env` file with the following environment variables:

```
####### sample deployment environment file #######

# Wormhole Core Contract Address
export RELEASE_WORMHOLE_ADDRESS=0x

# Circle Bridge Contract Address (TokenMessenger)
export RELEASE_CIRCLE_BRIDGE_ADDRESS=0x

# Circle Message Transmitter Address
export RELEASE_WORMHOLE_FINALITY=
```

Then run the following command to deploy (and set up) the proxy contract:

```
# sample deployment command
. env/put_your_env_file_here.env && PRIVATE_KEY=put_your_private_key_here bash shell-scripts/deploy_contracts.sh
```

## Test Suite

Run the Solidity-based unit tests:

```
make unit-test
```

Run the local-validator integration tests:

```
make integration-test
```

To run both the Solidity-based unit tests and the local-validator integration tests:

```
make test
```
