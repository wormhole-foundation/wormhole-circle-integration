# wormhole-circle-integration

### Disclaimer

This is an example repo and it should not be deployed to mainnet without additional testing and security auditing.

### Details

This repo demonstrates how to send USDC cross-chain (with or without additional instructions to be used by a contract) by using Wormhole's generic-messaging layer and by interacting with Circle's Cross-Chain Transfer Protocol.

### Compiling contracts

Install [Foundry tools](https://book.getfoundry.sh/getting-started/installation), which includes `forge`, `anvil` and `cast` CLI tools.

```
cd evm
make build
```

### Testnet Deployment

```
cd evm

# goerli
. env/eth-goerli-testnet.env && PRIVATE_KEY=put_your_private_key_here bash shell-scripts/deploy_usdc_integration.sh

# fuji
. env/avax-fuji-testnet.env && PRIVATE_KEY=put_your_private_key_here bash shell-scripts/deploy_usdc_integration.sh
```

### Structs

```
struct RedeemParameters {
    bytes encodedWormholeMessage;
    bytes circleBridgeMessage;
    bytes circleAttestation;
}

struct WormholeDeposit {
    uint8 payloadId;
    bytes32 token;
    uint256 amount;
    uint32 sourceDomain;
    uint32 targetDomain;
    uint64 nonce;
    bytes32 circleSender; // circle bridge on this chain
}

struct WormholeDepositWithPayload {
    WormholeDeposit depositHeader;
    bytes32 mintRecipient;
    bytes payload;
}

struct CircleDeposit {
    // Message Header
    uint32 version;
    uint32 sourceDomain;
    uint32 targetDomain;
    uint64 nonce;
    bytes32 circleSender;
    bytes32 circleReceiver;
    // End of Message Header
    // There should be an arbitrary length message following the header,
    // but we don't need to parse this message for verification purposes.
}
```

### API

```solidity
function transferTokens(
    address token,
    uint256 amount,
    uint16 targetChain,
    bytes32 mintRecipient
) public payable returns (uint64 messageSequence)

function transferTokensWithPayload(
    address token,
    uint256 amount,
    uint16 targetChain,
    bytes32 mintRecipient,
    bytes memory payload
) public payable returns (uint64 messageSequence)

function redeemTokens(RedeemParameters memory params) public

function redeemTokensWithPayload(
    RedeemParameters memory params
) public returns (WormholeDepositWithPayload memory wormholeDepositWithPayload)
```
