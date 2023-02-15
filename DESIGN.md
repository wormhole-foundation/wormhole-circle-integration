# Wormhole Circle Integration

## Objective

Integrate [Wormhole's Generic-Messaging Protocol](https://wormhole.com/) with Circle's [Cross-Chain Transfer Protocol](https://www.circle.com/en/pressroom/circle-enables-usdc-interoperability-for-developers-with-the-launch-of-cross-chain-transfer-protocol) to facilitate composable cross-chain transfers of Circle-supported assets.

## Background

The Circle Bridge allows users to send USDC and other Circle-supported assets cross chain by burning tokens on the source chain and minting the related token on the target chain (e.g. burn x amount of USDC on Ethereum and mint x amount of USDC on Avalanche).

Integrating Wormhole with Circle Bridge will permit users (xDapps) to transfer Circle-supported assets cross chain with an arbitrary message payload. This arbitrary payload can be used to disseminate instructions to the target contract to execute upon receiving minted tokens from the Circle Bridge.

## Goals

Implement smart contracts to perform the following actions:

- Interact with Circle Bridge to burn and mint Circle-supported assets.
- Emit Wormhole messages containing information about cross-chain transfers for Circle-supported assets.
  - Allow integrators to send an arbitrary message payload to the receiving contract.
- Mint tokens to a user-specified `mintRecipient` on the target chain.
- Ensure that only `WormholeCircleIntegration` contracts can invoke the Circle Transmitter contract on the target chain to mint tokens to the `mintRecipient`.

## Non-Goals

- Automatically relay Circle-supported asset transfers to the target chain.
- Automatically retrieve attestations from Circle's off-chain attestation service.
- Support assets not supported by the Circle Bridge.

## Detailed Design

To initiate a cross-chain transfer of Circle-supported assets, an integrator will invoke the `transferTokensWithPayload` method on the `WormholeCircleIntegration` contract. The `transferTokensWithPayload` method takes three arguments:

- `TransferParameters` - See [Structs](#structs) section of this document.
- `batchId` - ID for Wormhole message batching.
- `payload` - Arbitrary message payload to be delivered to the target chain.

The `transferTokensWithPayload` method will then complete the following actions in order:

1. Verify that the caller has provided enough native asset to pay the Wormhole protocol fee.
2. Transfer the `amount` of specified `token` from the caller to the contract.
3. Call the `depositForBurnWithCaller` method on the Circle Bridge to burn the `token`. This method takes an argument `_destinationCaller` which dictates who can complete the mint on the target chain. This argument is set to the target `WormholeCircleIntegration` contract address.
4. Encode and send the `DepositWithPayload` message (see [Payloads](#payloads)) via Wormhole.

Once the integrator has initiated a transfer (i.e. integrator submits transaction), they must fetch the attested Wormhole message and parse the transaction logs to locate a transfer message emitted by the Circle Bridge contract. Then the integrator must send a request to Circle's off-chain process with the transfer message to grab the attestation from the process's response (serialized EC signatures), which validates the token mint on the target chain. Integrators interacting with the `WormholeCircleIntegration` can streamline this process by writing a specialized off-chain relayer.

To complete the cross-chain transfer, the integrator invokes the `redeemTokensWithPayload` method on the target `WormholeCircleIntegration` contract, passing the `RedeemParameters` struct (see [Structs](#structs)) as an argument. The `redeemTokensWithPayload` method will complete the transfer by completing the following actions in order:

1. Verify that the Wormhole message was attested
2. Decode the Wormhole payload into the `DepositWithPayload` struct.
3. Verify that the contract caller is the `mintRecipient` encoded in the `DepositWithPayload` message.
4. Verify that message sender (`fromAddress`) is a registered `WormholeCircleIntegration` contract.
5. Verify that the correct message pair (Circle transfer message and Wormhole message) was delivered to the contract by comparing the `nonce`, `sourceDomain` and `targetDomain` values encoded in both messages.
6. Calls the Circle Transmitter contract method `receiveMessage` to mint tokens to the `mintRecipient`.
7. Return the `DepositWithPayload` struct to the caller.

After successfully executing the `redeemTokensWithPayload` method, the caller will now have custody of the newly minted tokens. They can then execute any additional instructions that were encoded in the `DepositWithPayload` message.

### API

```solidity
function transferTokensWithPayload(TransferParameters transferParams, uint32 batchId, bytes payload)

function redeemTokensWithPayload(RedeemParameters redeemParams)
```

### Governance API

```solidity
function updateWormholeFinality(bytes attestedGovernanceMessage)

function registerEmitterAndDomain(bytes attestedGovernanceMessage)

function upgradeContract(bytes attestedGovernanceMessage)

function verifyGovernanceMessage(bytes attestedGovernanceMessage, uint8 action)
```

### Structs

```solidity
struct TransferParameters {
    // address of token to be minted (32 bytes for non-EVM chains)
    address token;
    // amount of token to be minted
    uint256 amount;
    // Wormhole chain ID of target blockchain
    uint16 targetChain;
    // Recipient of minted tokens on the target blockchain
    bytes32 mintRecipient;
}

struct RedeemParameters {
    // Wormhole message emitted containing encoded `DepositWithPayload` message
    bytes encodedWormholeMessage;
    // Circle message emitted by the Circle Bridge after burning Circle-support assets
    bytes circleBridgeMessage;
    // Circle attestation (serialized EC Signatures)
    bytes circleAttestation;
}

struct DepositWithPayload {
    bytes32 token;
    uint256 amount;
    uint32 sourceDomain;
    uint32 targetDomain;
    uint64 nonce;
    bytes32 fromAddress;
    bytes32 mintRecipient;
    bytes payload;
}
```

### Payloads

DepositWithPayload:

```solidity
// payloadID uint8 = 1;
uint8 payloadID;

// Circle-supported token address, zero-left-padded for addresses less than 32 bytes long
bytes32 token;

// token amount
uint256 amount;

// Circle source domain
uint32 sourceDomain;

// Circle target domain
uint32 targetDomain;

// Circle transfer nonce
uint64 nonce;

// address of the `WormholeCircleIntegration` caller
bytes32 fromAddress;

// address of the token mint recipient on the target chain
bytes32 mintRecipient;

// length of the arbitrary message payload passed by the caller
uint16 payloadLength;

// arbitrary message payload passed by the caller
bytes payload;
```
