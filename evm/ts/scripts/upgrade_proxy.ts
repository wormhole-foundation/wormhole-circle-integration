import { ethers } from "ethers";
import yargs from "yargs";
import {
  ICircleIntegration,
  ICircleIntegration__factory,
} from "../src/ethers-contracts/index.js";
import { addSignerArgsParser, validateSignerArgs, getSigner } from "./signer.js";

interface Setup {
  circleIntegration: ICircleIntegration;
  governanceMessage: Buffer;
}

async function setUp(): Promise<Setup> {
  const parser = addSignerArgsParser(yargs())
    .help("help", "Upgrade Circle Integration Proxy")
    .env("CONFIGURE_CCTP")
    .option("proxy", {
      string: true,
      required: true,
      description: "Proxy Contract Address",
    })
    .option("governance-message", {
      required: true,
      string: true,
      description: "Signed Governance Message in base64 format",
    })
    .option("rpc", {
      string: true,
      required: true,
      description: "EVM RPC URL",
    });

  const parsedArgs = await parser.argv;
  const signerArgs = validateSignerArgs(parsedArgs);

  const provider = new ethers.providers.StaticJsonRpcProvider(parsedArgs.rpc);
  const signer = await getSigner(signerArgs, provider);
  const circleIntegration = ICircleIntegration__factory.connect(
    parsedArgs.proxy,
    signer,
  );

  return {
    circleIntegration,
    governanceMessage: Buffer.from(parsedArgs.governanceMessage, "base64"),
  };
}

async function main() {
  const { circleIntegration, governanceMessage } = await setUp();

  const chainId = await circleIntegration.chainId();
  console.log(
    `Executing mainnet CircleIntegration upgrade on chainId=${chainId}`,
  );

  const tx = await circleIntegration.upgradeContract(governanceMessage);
  console.log(`Upgrade transaction sent txHash=${tx.hash}`);

  const receipt = await tx.wait();
  if (receipt.status !== 1) {
    console.log("Failed transaction");
    return 1;
  } else {
    console.log("Transaction successful");
    return 0;
  }
}

main();
