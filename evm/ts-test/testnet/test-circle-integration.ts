require("dotenv").config({path: ".env"});
import {ethers} from "ethers";
import axios, {AxiosResponse} from "axios";
import {
  ChainId,
  CHAIN_ID_ETH,
  CHAIN_ID_AVAX,
  tryNativeToHexString,
  getEmitterAddressEth,
  getSignedVAAWithRetry,
} from "@certusone/wormhole-sdk";
import {NodeHttpTransport} from "@improbable-eng/grpc-web-node-http-transport";
import {abi as USDC_INTEGRATION_ABI} from "../../out/CircleIntegration.sol/CircleIntegration.json";
import {abi as RELAYER_ABI} from "./CircleRelayer.json";
import {abi as IERC20_ABI} from "../../out/IERC20.sol/IERC20.json";
import {abi as WORMHOLE_ABI} from "../../out/IWormhole.sol/IWormhole.json";

// consts fuji
const AVAX_PROVIDER = new ethers.providers.JsonRpcProvider(
  process.env.FUJI_PROVIDER
);
const AVAX_SIGNER = new ethers.Wallet(
  process.env.ETH_PRIVATE_KEY!,
  AVAX_PROVIDER
);
const AVAX_CONTRACT_ADDRESS = "0x61e71a87b492c5545844079ff205e025c3c7b5e8";
const AVAX_TRANSMITTER_ADDRESS = "0x52FfFb3EE8Fa7838e9858A2D5e454007b9027c3C";
const AVAX_USDC_ADDRESS = "0x5425890298aed601595a70AB815c96711a31Bc65";
const WORMHOLE_AVAX = "0x7bbcE28e64B3F8b84d876Ab298393c38ad7aac4C";
const AVAX_DOMAIN: number = 1;

// create the USDC integration contract
const ETH_PROVIDER = new ethers.providers.JsonRpcProvider(
  process.env.GOERLI_PROVIDER
);
const ETH_SIGNER = new ethers.Wallet(
  process.env.ETH_PRIVATE_KEY!,
  ETH_PROVIDER
);
const ETH_CONTRACT_ADDRESS = "0xaf2983e1e5bb6ef02c8a48d4666fde7bbac878be";
const ETH_USDC_ADDRESS = "0x07865c6E87B9F70255377e024ace6630C1Eaa37F";
const ETH_DOMAIN: number = 0;

// relayer contracts
const AVAX_RELAYER_ADDRESS = "0x65d1f890fea9a03a0fda808f3f7de60dcda38612";
const ETH_RELAYER_ADDRESS = "0xc3e75d6a04596c662aed199e93f876749c21ae5d";

// wormhole
export const WORMHOLE_RPC_HOSTS = [
  "https://wormhole-v2-testnet-api.certus.one",
];
let AVAX_WORMHOLE_CONTRACT = new ethers.Contract(
  WORMHOLE_AVAX,
  WORMHOLE_ABI,
  AVAX_PROVIDER
);
AVAX_WORMHOLE_CONTRACT = AVAX_WORMHOLE_CONTRACT.connect(AVAX_SIGNER);

// avax contracts
let USDC_INTEGRATION_SOURCE = new ethers.Contract(
  AVAX_CONTRACT_ADDRESS,
  USDC_INTEGRATION_ABI,
  AVAX_PROVIDER
);
USDC_INTEGRATION_SOURCE = USDC_INTEGRATION_SOURCE.connect(AVAX_SIGNER);

// eth contracts
let USDC_INTEGRATION_TARGET = new ethers.Contract(
  ETH_CONTRACT_ADDRESS,
  USDC_INTEGRATION_ABI,
  AVAX_PROVIDER
);
USDC_INTEGRATION_TARGET = USDC_INTEGRATION_TARGET.connect(ETH_SIGNER);

// create USDC contract to approve
let USDC_CONTRACT = new ethers.Contract(
  AVAX_USDC_ADDRESS,
  IERC20_ABI,
  AVAX_PROVIDER
);
USDC_CONTRACT = USDC_CONTRACT.connect(AVAX_SIGNER);

// avax relayer contracts
let RELAYER_SOURCE = new ethers.Contract(
  AVAX_RELAYER_ADDRESS,
  RELAYER_ABI,
  AVAX_PROVIDER
);
RELAYER_SOURCE = RELAYER_SOURCE.connect(AVAX_SIGNER);

// eth relayer contracts
let RELAYER_TARGET = new ethers.Contract(
  ETH_RELAYER_ADDRESS,
  RELAYER_ABI,
  ETH_PROVIDER
);
RELAYER_TARGET = RELAYER_TARGET.connect(ETH_SIGNER);

// wormhole event ABIs
export const WORMHOLE_MESSAGE_EVENT_ABI = [
  "event LogMessagePublished(address indexed sender, uint64 sequence, uint32 nonce, bytes payload, uint8 consistencyLevel)",
];

// circle event ABIS
export const CIRCLE_MESSAGE_SENT_ABI = ["event MessageSent(bytes message)"];

export async function parseEventFromAbi(
  log_: ethers.providers.Log,
  eventAbi: string[]
): Promise<ethers.utils.LogDescription> {
  // create the wormhole message interface
  const interface_ = new ethers.utils.Interface(eventAbi);
  return interface_.parseLog(log_);
}

export async function parseCircleMessageEvent(
  receipt: ethers.ContractReceipt,
  circleTransmitter: string
): Promise<ethers.utils.LogDescription> {
  let circleMessageEvent: ethers.utils.LogDescription = null!;

  for (const log of receipt.logs) {
    if (log.address == circleTransmitter) {
      circleMessageEvent = await parseEventFromAbi(
        log,
        CIRCLE_MESSAGE_SENT_ABI
      );
    }
  }
  return circleMessageEvent;
}

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function getCircleAttestation(
  messageHash: ethers.BytesLike
): Promise<ethers.BytesLike> {
  while (true) {
    // get the post
    let response: AxiosResponse = await axios.get(
      `https://iris-api-sandbox.circle.com/attestations/${messageHash}`
    );

    if (response.status != 200) {
      console.log(
        "Failed to get attestation from circle, sleeping for 5 seconds"
      );
      await sleep(5000);
    }

    if (response.data.status == "pending_confirmations") {
      console.log(
        "Waiting for confirmations from circle, sleeping for 5 seconds."
      );
      await sleep(5000);
    }

    if (response.data.status == "complete") {
      return response.data.attestation;
    }
  }
}

export async function parseWormholeEventsFromReceipt(
  receipt: ethers.ContractReceipt,
  wormhole: ethers.BytesLike
): Promise<ethers.utils.LogDescription[]> {
  let wormholeEvents: ethers.utils.LogDescription[] = [];
  for (const log of receipt.logs) {
    if (log.address == wormhole) {
      wormholeEvents.push(
        await parseEventFromAbi(log, WORMHOLE_MESSAGE_EVENT_ABI)
      );
    }
  }
  return wormholeEvents;
}

export async function getSignedVaaFromReceiptOnEth(
  receipt: ethers.ContractReceipt,
  emitterChainId: ChainId,
  contractAddress: ethers.BytesLike,
  wormholeAddress: ethers.BytesLike
): Promise<Uint8Array> {
  const messageEvents = await parseWormholeEventsFromReceipt(
    receipt,
    wormholeAddress
  );

  console.log(messageEvents);

  // grab the sequence from the parsed message log
  if (messageEvents.length !== 1) {
    throw Error("more than one message found in log");
  }
  const sequence = messageEvents[0].args.sequence;

  // fetch the signed VAA
  const result = await getSignedVAAWithRetry(
    WORMHOLE_RPC_HOSTS,
    emitterChainId,
    getEmitterAddressEth(contractAddress),
    sequence.toString(),
    {
      transport: NodeHttpTransport(),
    }
  );
  return result.vaaBytes;
}

async function registerEmitter(
  contract: ethers.Contract,
  targetChainId: ChainId,
  targetContractAddress: ethers.utils.BytesLike,
  targetContractDomain: number
) {
  // register the target contract
  console.log("Registering chain.");
  const tx = await contract.registerEmitter(
    targetChainId,
    targetContractAddress
  );
  await tx.wait();

  // register the target domain
  console.log("Registering domain.");
  const tx2 = await contract.registerChainDomain(
    targetChainId,
    targetContractDomain
  );
  await tx2.wait();
}

async function updateFinality(
  contract: ethers.Contract,
  chainId: ChainId,
  newFinality: number
) {
  console.log("Updating finality");

  const tx = await contract.updateWormholeFinality(chainId, newFinality);
  await tx.wait();
}

async function registerToken(contract: ethers.Contract, token: string) {
  console.log(`Registering token: ${token}`);

  const tx = await contract.registerAcceptedToken(token);
  await tx.wait();
}

async function registerTargetToken(
  contract: ethers.Contract,
  sourceToken: string,
  targetChainId: ChainId,
  targetToken: string
) {
  console.log(`Registering target token: ${targetToken}`);

  const tx = await contract.registerTargetChainToken(
    sourceToken,
    targetChainId,
    targetToken
  );
  await tx.wait();
}

async function registerRelayerContract(
  contract: ethers.Contract,
  targetChainId: ChainId,
  targetContractAddress: string
) {
  console.log(`Registering relayer: ${targetContractAddress}`);

  const tx = await contract.registerContract(
    targetChainId,
    "0x" + tryNativeToHexString(targetContractAddress, targetChainId)
  );
  await tx.wait();
}

async function updateRelayerFee(
  contract: ethers.Contract,
  chainId: ChainId,
  address: string,
  amount: ethers.BigNumberish
) {
  console.log(
    `Updating relayer fee chain=${chainId}, amount=${amount.toString()}`
  );

  const tx = await contract.updateRelayerFee(chainId, address, amount);
  await tx.wait();
}

async function updateNativeSwapRate(
  contract: ethers.Contract,
  token: string,
  amount: ethers.BigNumberish
) {
  console.log(`Updating swap rate token=${token}, amount=${amount.toString()}`);

  const tx = await contract.updateNativeSwapRate(token, amount);
  await tx.wait();
}

async function updateMaxSwapRate(
  contract: ethers.Contract,
  token: string,
  amount: ethers.BigNumberish
) {
  console.log(
    `Updating max swap amount token=${token}, amount=${amount.toString()}`
  );

  const tx = await contract.updateMaxSwapAmount(token, amount);
  await tx.wait();
}

async function registerEverything() {
  // make sure the USDC integration contracts have been registered, domains have been set
  await registerEmitter(
    USDC_INTEGRATION_SOURCE,
    CHAIN_ID_ETH,
    "0x" + tryNativeToHexString(ETH_CONTRACT_ADDRESS, CHAIN_ID_ETH),
    ETH_DOMAIN
  );
  await registerEmitter(
    USDC_INTEGRATION_TARGET,
    CHAIN_ID_AVAX,
    "0x" + tryNativeToHexString(AVAX_CONTRACT_ADDRESS, CHAIN_ID_AVAX),
    AVAX_DOMAIN
  );
  await registerEmitter(
    USDC_INTEGRATION_SOURCE,
    CHAIN_ID_AVAX,
    "0x" + tryNativeToHexString(AVAX_CONTRACT_ADDRESS, CHAIN_ID_AVAX),
    AVAX_DOMAIN
  );
  await registerEmitter(
    USDC_INTEGRATION_TARGET,
    CHAIN_ID_ETH,
    "0x" + tryNativeToHexString(ETH_CONTRACT_ADDRESS, CHAIN_ID_ETH),
    ETH_DOMAIN
  );
}

export interface RedeemParameters {
  encodedWormholeMessage: ethers.BytesLike;
  circleBridgeMessage: ethers.BytesLike;
  circleAttestation: ethers.BytesLike;
}

export interface TransferParameters {
  token: string;
  amount: ethers.BigNumber;
  targetChain: number;
  mintRecipient: ethers.BytesLike;
}

async function transferTokensWithPayload() {
  // struct to call target chain `redeemTokens` method with
  const redeemParams = {} as RedeemParameters;

  // input params to transferTokens
  const amount: ethers.BigNumber = ethers.utils.parseUnits("0.000001", 6);
  const toChain = CHAIN_ID_ETH;
  const mintRecipient =
    "0x" + tryNativeToHexString(ETH_SIGNER.address, CHAIN_ID_ETH);
  const batchId: ethers.BigNumber = ethers.BigNumber.from("0");

  const transferParams: TransferParameters = {
    token: AVAX_USDC_ADDRESS,
    amount: amount,
    targetChain: toChain,
    mintRecipient:
      "0x" + tryNativeToHexString(ETH_SIGNER.address, CHAIN_ID_ETH),
  };

  // create an arbitrary payload to test with
  const arbitraryPayload = ethers.utils.hexlify(
    ethers.utils.toUtf8Bytes("SuperCoolCrossChainStuff0")
  );

  // approve the contract to spend USDC
  const tx = await USDC_CONTRACT.approve(
    USDC_INTEGRATION_SOURCE.address,
    amount
  );
  await tx.wait();

  // depositForBurn (transferTokens)
  const tx2 = await USDC_INTEGRATION_SOURCE.transferTokensWithPayload(
    transferParams,
    batchId,
    arbitraryPayload
  );
  const receipt: ethers.ContractReceipt = await tx2.wait();

  console.log(
    `Deposit for burn transaction on Avax: ${receipt.transactionHash}`
  );

  // fetch the wormhole VAA
  redeemParams.encodedWormholeMessage = await getSignedVaaFromReceiptOnEth(
    receipt,
    CHAIN_ID_AVAX,
    USDC_INTEGRATION_SOURCE.address,
    WORMHOLE_AVAX
  );

  // parse the wormhole message to verify that the payload is correct
  const parsedWormholeMessage = await AVAX_WORMHOLE_CONTRACT.parseVM(
    redeemParams.encodedWormholeMessage
  );
  const parsedPayload =
    await USDC_INTEGRATION_TARGET.decodeWormholeDepositWithPayload(
      parsedWormholeMessage.payload
    );

  console.log(parsedPayload);

  // parse the circle message event from the MessageTransmitter contract
  const circleEvent = await parseCircleMessageEvent(
    receipt,
    AVAX_TRANSMITTER_ADDRESS
  );

  // hash the circleEvent message field from the event
  const circleEventHash = ethers.utils.keccak256(circleEvent.args.message);

  // sleep for 10 seconds, then fetch the attestation from circle
  console.log(`Searching for attestation: ${circleEventHash}`);
  await sleep(10000);
  const circleAttestation = await getCircleAttestation(circleEventHash);

  // set cricle values in redeemParams
  redeemParams.circleBridgeMessage = circleEvent.args.message;
  redeemParams.circleAttestation = circleAttestation;

  // redeem the tokens on the target chain
  const tx3 = await USDC_INTEGRATION_TARGET.redeemTokensWithPayload(
    redeemParams
  );
  const receipt2: ethers.ContractReceipt = await tx3.wait();

  console.log(`Mint transaction on Eth: ${receipt2.transactionHash}`);
}

async function transferTokensWithRelay(
  amount_: string,
  toNativeAmount_: string
) {
  // struct to call target chain `redeemTokens` method with
  const redeemParams = {} as RedeemParameters;

  // input params to transferTokens
  const amount: ethers.BigNumber = ethers.utils.parseUnits(amount_, 6);
  const toNativeAmount: ethers.BigNumber = ethers.utils.parseUnits(
    toNativeAmount_,
    6
  );
  const toChain = CHAIN_ID_ETH;

  // create signing key and derive public key
  const targetRecipientAddress =
    "0x" + tryNativeToHexString(ETH_SIGNER.address, CHAIN_ID_ETH);

  // approve the contract to spend USDC
  const tx = await USDC_CONTRACT.approve(RELAYER_SOURCE.address, amount);
  await tx.wait();

  // depositForBurn (transferTokens)
  const tx2 = await RELAYER_SOURCE.transferTokensWithRelay(
    AVAX_USDC_ADDRESS,
    amount,
    toNativeAmount,
    toChain,
    targetRecipientAddress
  );
  const receipt: ethers.ContractReceipt = await tx2.wait();

  console.log(
    `Deposit for burn transaction on Avax: ${receipt.transactionHash}`
  );

  // fetch the wormhole VAA
  console.log("Searching for VAA.");
  redeemParams.encodedWormholeMessage = await getSignedVaaFromReceiptOnEth(
    receipt,
    CHAIN_ID_AVAX,
    USDC_INTEGRATION_SOURCE.address,
    WORMHOLE_AVAX
  );

  // parse the wormhole message to verify that the payload is correct
  const parsedWormholeMessage = await AVAX_WORMHOLE_CONTRACT.parseVM(
    redeemParams.encodedWormholeMessage
  );
  const parsedPayload = await USDC_INTEGRATION_TARGET.decodeDepositWithPayload(
    parsedWormholeMessage.payload
  );

  console.log(parsedPayload);

  // parse the circle message event from the MessageTransmitter contract
  const circleEvent = await parseCircleMessageEvent(
    receipt,
    AVAX_TRANSMITTER_ADDRESS
  );

  // hash the circleEvent message field from the event
  const circleEventHash = ethers.utils.keccak256(circleEvent.args.message);

  // sleep for 10 seconds, then fetch the attestation from circle
  console.log(`Searching for attestation: ${circleEventHash}`);
  await sleep(10000);
  const circleAttestation = await getCircleAttestation(circleEventHash);

  // set cricle values in redeemParams
  redeemParams.circleBridgeMessage = circleEvent.args.message;
  redeemParams.circleAttestation = circleAttestation;

  // fetch swap quote
  const swapQuote = await RELAYER_TARGET.calculateNativeSwapAmount(
    ETH_USDC_ADDRESS,
    toNativeAmount
  );

  // redeem the tokens on the target chain
  const tx3 = await RELAYER_TARGET.redeemTokens(redeemParams, {
    value: swapQuote,
  });
  const receipt2: ethers.ContractReceipt = await tx3.wait();

  console.log(`Mint transaction on Eth: ${receipt2.transactionHash}`);
}

async function main() {
  // await registerEverything();
  // await updateFinality(USDC_INTEGRATION_TARGET, CHAIN_ID_ETH, 200);
  // await registerToken(USDC_INTEGRATION_SOURCE, AVAX_USDC_ADDRESS);
  // await registerToken(USDC_INTEGRATION_TARGET, ETH_USDC_ADDRESS);
  // await registerTargetToken(USDC_INTEGRATION_SOURCE, AVAX_USDC_ADDRESS, CHAIN_ID_ETH, ETH_USDC_ADDRESS);
  // await registerTargetToken(USDC_INTEGRATION_TARGET, ETH_USDC_ADDRESS, CHAIN_ID_AVAX, AVAX_USDC_ADDRESS);
  // await transferTokensWithPayload();

  // // AVAX relayer fees
  await transferTokensWithRelay("1", "0");
}

main();
