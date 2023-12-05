import { ArgumentParser, Namespace } from "argparse";
import { ethers } from "ethers";
import {
  ICircleIntegration,
  ICircleIntegration__factory,
} from "../src/ethers-contracts";

interface Setup {
  circleIntegration: ICircleIntegration;
  governanceMessage: Buffer;
}

function setUp(): Setup {
  const parser = new ArgumentParser({
    description: "Upgrade Circle Integration Proxy",
  });

  parser.add_argument("-m", "--governance-message", {
    required: true,
    help: "Signed Governance Message",
  });
  parser.add_argument("-p", "--proxy", {
    required: true,
    help: "Proxy Contract Address",
  });
  parser.add_argument("--rpc-url", { required: true, help: "EVM RPC" });
  parser.add_argument("--private-key", {
    required: true,
    help: "EVM Private Key",
  });

  const args: Namespace = parser.parse_args();

  const provider = new ethers.providers.StaticJsonRpcProvider(args.rpc_url);
  const wallet = new ethers.Wallet(args.private_key, provider);
  const circleIntegration = ICircleIntegration__factory.connect(
    args.proxy,
    wallet
  );

  return {
    circleIntegration,
    governanceMessage: Buffer.from(args.governance_message, "hex"),
  };
}

async function main() {
  const { circleIntegration, governanceMessage } = setUp();

  const chainId = await circleIntegration.chainId();
  console.log(chainId);

  const tx = circleIntegration
    .upgradeContract(governanceMessage)
    .then((tx) => tx.wait())
    .catch((msg) => {
      // should not happen
      console.log(msg);
      return null;
    });
  if (tx === null) {
    console.log("failed transaction");
    return 1;
  } else {
    return 0;
  }
}

main();
