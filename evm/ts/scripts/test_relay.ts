import {ArgumentParser, Namespace} from "argparse";
import {ethers} from "ethers";
import {
  ICircleIntegration,
  ICircleIntegration__factory,
} from "../src/ethers-contracts";
import {AxiosResponse} from "axios";
const axios = require("axios");

import {
  ChainId,
  getSignedVAAWithRetry,
  getEmitterAddressEth,
  uint8ArrayToHex,
} from "@certusone/wormhole-sdk";

const WORMHOLE_RPC_HOSTS = ["https://wormhole-v2-mainnet-api.certus.one"];

const CIRCLE_EMITTER_ADDRESSES = {
  [2]: "0x0a992d191DEeC32aFe36203Ad87D7d289a738F81",
  [6]: "0x8186359af5f57fbb40c6b14a588d2a59c0c29880",
};

const CIRCLE_INTEGRATION_ADDRESSES = {
  [2]: "0xaada05bd399372f0b0463744c09113c137636f6a",
  [6]: "0x09fb06a271faff70a651047395aaeb6265265f13",
};

interface Setup {
  fromContract: ICircleIntegration;
  toContract: ICircleIntegration;
  txHash: string;
  sequence: number;
}

function setUp(): Setup {
  const parser = new ArgumentParser({
    description: "Upgrade Circle Integration Proxy",
  });
  parser.add_argument("--from", {
    required: true,
    help: "Proxy Contract Chain",
  });
  parser.add_argument("--to", {
    required: true,
    help: "Proxy Contract Chain",
  });
  parser.add_argument("--tx", {
    required: true,
    help: "Transaction Hash",
  });
  parser.add_argument("--sequence", {
    required: true,
    help: "Wormhole Sequence",
  });
  parser.add_argument("--from-rpc", {required: true, help: "EVM RPC"});
  parser.add_argument("--to-rpc", {required: true, help: "EVM RPC"});
  parser.add_argument("--key", {
    required: true,
    help: "EVM Private Key",
  });

  const args: Namespace = parser.parse_args();

  // Set up providers.
  const fromProvider = new ethers.providers.StaticJsonRpcProvider(
    args.from_rpc
  );
  const toProvider = new ethers.providers.StaticJsonRpcProvider(args.to_rpc);

  // Set up wallets.
  const fromWallet = new ethers.Wallet(args.key, fromProvider);
  const toWallet = new ethers.Wallet(args.key, toProvider);

  // Contracts.
  const fromContract = ICircleIntegration__factory.connect(
    CIRCLE_INTEGRATION_ADDRESSES[args.from as 2 | 6],
    fromWallet
  );
  const toContract = ICircleIntegration__factory.connect(
    CIRCLE_INTEGRATION_ADDRESSES[args.to as 2 | 6],
    toWallet
  );
  const txHash = args.tx as string;
  const sequence = args.sequence as number;

  return {
    fromContract,
    toContract,
    txHash,
    sequence,
  };
}

async function sleep(timeout: number) {
  return new Promise((resolve) => setTimeout(resolve, timeout));
}

async function getCircleAttestation(
  messageHash: ethers.BytesLike,
  timeout: number = 2000
) {
  while (true) {
    // get the post
    const response = await axios
      .get(`http://iris-api.circle.com/attestations/${messageHash}`)
      .catch((e: any) => {
        return null;
      })
      .then(async (response: AxiosResponse | null) => {
        if (
          response !== null &&
          response.status === 200 &&
          response.data.status === "complete"
        ) {
          return response.data.attestation as string;
        }

        return null;
      });

    if (response !== null) {
      return response;
    }

    await sleep(timeout);
  }
}

async function handleCircleMessageInLogs(
  logs: ethers.providers.Log[],
  circleEmitterAddress: string
): Promise<[string | null, string | null]> {
  const circleMessage = findCircleMessageInLogs(logs, circleEmitterAddress);
  if (circleMessage === null) {
    return [null, null];
  }

  const circleMessageHash = ethers.utils.keccak256(circleMessage);
  const signature = await getCircleAttestation(circleMessageHash);

  return [circleMessage, signature];
}

function findCircleMessageInLogs(
  logs: ethers.providers.Log[],
  circleEmitterAddress: string
): string | null {
  for (const log of logs) {
    if (log.address === ethers.utils.getAddress(circleEmitterAddress)) {
      const messageSentIface = new ethers.utils.Interface([
        "event MessageSent(bytes message)",
      ]);
      return messageSentIface.parseLog(log).args.message as string;
    }
  }

  return null;
}

async function main() {
  const {fromContract, toContract, txHash, sequence} = setUp();

  const chainId = await fromContract.chainId();
  console.log(chainId, sequence, txHash);

  // Fetch the ethereum transaction receipt.
  const receipt = await fromContract.provider.getTransactionReceipt(txHash);

  // Fetch the wormhole message.
  console.log("Fetching Wormhole message");
  const {vaaBytes} = await getSignedVAAWithRetry(
    WORMHOLE_RPC_HOSTS,
    chainId as ChainId,
    getEmitterAddressEth(fromContract.address),
    sequence.toString()
  );
  console.log("VAA Found!");

  // Fetch the circle message.
  console.log("Fetching Circle attestation");
  const [circleBridgeMessage, circleAttestation] =
    await handleCircleMessageInLogs(
      receipt.logs,
      CIRCLE_EMITTER_ADDRESSES[chainId as 2 | 6]
    );

  // Redeem parameters for target function call.
  const redeemParameters = {
    encodedWormholeMessage: `0x${uint8ArrayToHex(vaaBytes)}`,
    circleBridgeMessage: circleBridgeMessage as string,
    circleAttestation: circleAttestation as string,
  };
  console.log("All redeem parameters have been located");

  // Complete the transfer.
  const tx: ethers.ContractTransaction =
    await toContract.redeemTokensWithPayload(redeemParameters);
  const redeedReceipt: ethers.ContractReceipt = await tx.wait();
  console.log(`Redeemed transfer in txhash: ${redeedReceipt.transactionHash}`);
}

main();
