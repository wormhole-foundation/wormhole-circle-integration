# wormhole-circle-integration

### Details

This repo demonstrates how to send USDC cross-chain (with additional instructions to be used by a contract) by using Wormhole's generic-messaging layer and by interacting with Circle's Cross-Chain Transfer Protocol.

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
. env/eth-goerli-testnet.env && PRIVATE_KEY=put_your_private_key_here bash shell-scripts/deploy_circle_integration.sh

# fuji
. env/avax-fuji-testnet.env && PRIVATE_KEY=put_your_private_key_here bash shell-scripts/deploy_circle_integration.sh
```

### Deployed Contract Addresses

```
goerli: 0xdbedb4ebd098e9f1777af9f8088e794d381309d1
fuji: 0x3e6a4543165aaecbf7ffc81e54a1c7939cb12cb8
```

### Structs

```
struct TransferParameters {
    address token;
    uint256 amount;
    uint16 targetChain;
    bytes32 mintRecipient;
}

struct RedeemParameters {
    bytes encodedWormholeMessage;
    bytes circleBridgeMessage;
    bytes circleAttestation;
}

// payload ID == 1
struct DepositWithPayload {
    bytes32 token;
    uint256 amount;
    uint32 sourceDomain;
    uint32 targetDomain;
    uint64 nonce;
    bytes32 mintRecipient;
    bytes payload;
}
```

### API

```solidity
function transferTokensWithPayload(
    TransferParameters memory transferParams,
    uint32 batchId,
    bytes memory payload
) public payable returns (uint64 messageSequence)

function redeemTokensWithPayload(
    RedeemParameters memory params
) public returns (DepositWithPayload memory depositWithPayload)
```
