import { ethers } from "ethers";
import yargs from "yargs";
import { hideBin } from "yargs/helpers";
import {
  ICircleIntegration,
  ICircleIntegration__factory,
} from "../src/ethers-contracts/index.js";
import { addSignerArgsParser, validateSignerArgs, getSigner } from "./signer.js";
import { createCircleIntegrationUpgradeVAA, GuardianSet } from "./sign_vaa.js";

interface Setup {
  circleIntegration: ICircleIntegration;
  newImplementation: string;
  guardians: string[];
}

async function setUp(): Promise<Setup> {
  const parser = addSignerArgsParser(yargs())
    .help("help", "Upgrade testnet Circle Integration Proxy")
    .env("CONFIGURE_CCTP")
    .option("proxy", {
      string: true,
      required: true,
      description: "Proxy Contract Address",
    })
    .option("new-implementation", {
      string: true,
      required: true,
      description: "New implementation contract address",
    })
    .option("guardian", {
      array: true,
      string: true,
      required: true,
      description: `Guardian private key in hexadecimal format.
If there is more than one guardian, they must be sorted by their guardian set index.
Skipping indexes in the guardian set is not supported.`,
    })
    .option("rpc", {
      string: true,
      required: true,
      description: "EVM RPC URL",
    });

  const parsedArgs = await parser.parse(hideBin(process.argv));
  if (!ethers.utils.isAddress(parsedArgs.newImplementation)) {
    throw new Error(
      `The implementation address is invalid: ${parsedArgs.newImplementation}`,
    );
  }
  const signerArgs = validateSignerArgs(parsedArgs);

  const provider = new ethers.providers.StaticJsonRpcProvider(parsedArgs.rpc);
  const signer = await getSigner(signerArgs, provider);
  const circleIntegration = ICircleIntegration__factory.connect(
    parsedArgs.proxy,
    signer,
  );

  return {
    circleIntegration,
    newImplementation: parsedArgs.newImplementation,
    guardians: parsedArgs.guardian,
  };
}

async function main() {
  const { circleIntegration, newImplementation, guardians } = await setUp();

  const chainId = await circleIntegration.chainId();
  console.log(
    `Executing testnet CircleIntegration upgrade on chainId=${chainId}`,
  );

  const guardianSet: GuardianSet = {
    id: 0,
    guardians: guardians.map((guardian, index) => {
      return { key: guardian, index };
    }),
  };

  const governanceMessage = await createCircleIntegrationUpgradeVAA(
    chainId,
    newImplementation,
    guardianSet,
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
