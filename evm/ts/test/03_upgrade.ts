import {expect} from "chai";
import {ethers} from "ethers";
import {tryNativeToUint8Array} from "@certusone/wormhole-sdk";
import {
  GUARDIAN_PRIVATE_KEY,
  WORMHOLE_GUARDIAN_SET_INDEX,
  ETH_LOCALHOST,
  WALLET_PRIVATE_KEY,
  AVAX_LOCALHOST,
  ETH_FORK_CHAIN_ID,
  AVAX_FORK_CHAIN_ID,
} from "./helpers/consts";
import {ICircleIntegration__factory} from "../src/ethers-contracts";
import {MockGuardians} from "@certusone/wormhole-sdk/lib/cjs/mock";

import {CircleGovernanceEmitter} from "./helpers/mock";
import {getTimeNow, readCircleIntegrationProxyAddress} from "./helpers/utils";

const {execSync} = require("child_process");

describe("Circle Integration Implementation Upgrade", () => {
  // ethereum wallet, CircleIntegration contract and USDC contract
  const ethProvider = new ethers.providers.StaticJsonRpcProvider(ETH_LOCALHOST);
  const ethWallet = new ethers.Wallet(WALLET_PRIVATE_KEY, ethProvider);
  const ethProxyAddress = readCircleIntegrationProxyAddress(ETH_FORK_CHAIN_ID);
  const ethCircleIntegration = ICircleIntegration__factory.connect(
    ethProxyAddress,
    ethWallet
  );

  // avalanche wallet, CircleIntegration contract and USDC contract
  const avaxProvider = new ethers.providers.StaticJsonRpcProvider(
    AVAX_LOCALHOST
  );
  const avaxWallet = new ethers.Wallet(WALLET_PRIVATE_KEY, avaxProvider);
  const avaxProxyAddress =
    readCircleIntegrationProxyAddress(AVAX_FORK_CHAIN_ID);
  const avaxCircleIntegration = ICircleIntegration__factory.connect(
    avaxProxyAddress,
    avaxWallet
  );

  // MockGuardians and MockCircleAttester objects
  const guardians = new MockGuardians(WORMHOLE_GUARDIAN_SET_INDEX, [
    GUARDIAN_PRIVATE_KEY,
  ]);

  const newImplementations = new Map<string, string>();

  describe("Run `yarn deploy-implementation-only`", () => {
    describe("Ethereum Goerli Testnet", () => {
      it("Deploy", async () => {
        const output = execSync(
          `RPC=${ETH_LOCALHOST} PRIVATE_KEY=${WALLET_PRIVATE_KEY} yarn deploy-implementation-only`
        ).toString();
        const address = output.match(
          /CircleIntegrationImplementation: (0x[A-Fa-f0-9]+)/
        )[1];
        newImplementations.set("ethereum", address);
      });
    });

    describe("Avalanche Fuji Testnet", () => {
      it("Deploy", async () => {
        const output = execSync(
          `RPC=${AVAX_LOCALHOST} PRIVATE_KEY=${WALLET_PRIVATE_KEY} yarn deploy-implementation-only`
        ).toString();
        const address = output.match(
          /CircleIntegrationImplementation: (0x[A-Fa-f0-9]+)/
        )[1];
        newImplementations.set("avalanche", address);
      });
    });
  });

  describe("Run `yarn upgrade-proxy`", () => {
    // produces governance VAAs for CircleAttestation contract
    const governance = new CircleGovernanceEmitter();

    describe("Ethereum Goerli Testnet", () => {
      const chainName = "ethereum";

      it("Upgrade", async () => {
        const timestamp = getTimeNow();
        const chainId = await ethCircleIntegration.chainId();
        const newImplementation = newImplementations.get(chainName);
        expect(newImplementation).is.not.undefined;

        {
          const initialized = await ethCircleIntegration.isInitialized(
            newImplementation!
          );
          expect(initialized).is.false;
        }

        // create unsigned upgradeContract governance message
        const published = governance.publishCircleIntegrationUpgradeContract(
          timestamp,
          chainId,
          tryNativeToUint8Array(newImplementation!, chainName)
        );

        // sign governance message with guardian key
        const signedMessage = guardians.addSignatures(published, [0]);

        // upgrade contract with new implementation
        execSync(
          `yarn upgrade-proxy \
            --rpc-url ${ETH_LOCALHOST} \
            --private-key ${WALLET_PRIVATE_KEY} \
            --proxy ${ethProxyAddress} \
            --governance-message ${signedMessage.toString("hex")}`
        );

        {
          const initialized = await ethCircleIntegration.isInitialized(
            newImplementation!
          );
          expect(initialized).is.true;
        }
      });
    });

    describe("Avalanche Fuji Testnet", () => {
      const chainName = "avalanche";

      it("Upgrade", async () => {
        const timestamp = getTimeNow();
        const chainId = await avaxCircleIntegration.chainId();
        const newImplementation = newImplementations.get(chainName);
        expect(newImplementation).is.not.undefined;

        {
          const initialized = await avaxCircleIntegration.isInitialized(
            newImplementation!
          );
          expect(initialized).is.false;
        }

        // create unsigned upgradeContract governance message
        const published = governance.publishCircleIntegrationUpgradeContract(
          timestamp,
          chainId,
          tryNativeToUint8Array(newImplementation!, chainName)
        );

        // sign governance message with guardian key
        const signedMessage = guardians.addSignatures(published, [0]);

        // upgrade contract with new implementation
        execSync(
          `yarn upgrade-proxy \
            --rpc-url ${AVAX_LOCALHOST} \
            --private-key ${WALLET_PRIVATE_KEY} \
            --proxy ${avaxProxyAddress} \
            --governance-message ${signedMessage.toString("hex")}`
        );

        {
          const initialized = await avaxCircleIntegration.isInitialized(
            newImplementation!
          );
          expect(initialized).is.true;
        }
      });
    });
  });
});
