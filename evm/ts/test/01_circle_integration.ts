import { expect } from "chai";
import { ethers } from "ethers";
import {
  tryNativeToHexString,
  tryNativeToUint8Array,
} from "@certusone/wormhole-sdk";
import {
  AVAX_USDC_TOKEN_ADDRESS,
  ETH_USDC_TOKEN_ADDRESS,
  GUARDIAN_PRIVATE_KEY,
  WORMHOLE_GUARDIAN_SET_INDEX,
  ETH_LOCALHOST,
  WALLET_PRIVATE_KEY,
  ETH_WORMHOLE_ADDRESS,
  AVAX_LOCALHOST,
  ETH_FORK_CHAIN_ID,
  AVAX_FORK_CHAIN_ID,
} from "./helpers/consts";
import {
  IWormhole__factory,
  ICircleIntegration__factory,
} from "../src/ethers-contracts";
import { MockGuardians } from "@certusone/wormhole-sdk/lib/cjs/mock";
import { MockCircleIntegration, CircleGovernanceEmitter } from "./helpers/mock";
import { getTimeNow } from "./helpers/utils";
import * as fs from "fs";

describe("Circle Integration Test", () => {
  // ethereum
  const ethProvider = new ethers.providers.StaticJsonRpcProvider(ETH_LOCALHOST);
  const ethWallet = new ethers.Wallet(WALLET_PRIVATE_KEY, ethProvider);
  const ethCircleIntegration = ICircleIntegration__factory.connect(
    readCircleIntegrationProxyAddress(ETH_FORK_CHAIN_ID),
    ethWallet
  );

  // avalanche
  const avaxProvider = new ethers.providers.StaticJsonRpcProvider(
    AVAX_LOCALHOST
  );
  const avaxWallet = new ethers.Wallet(WALLET_PRIVATE_KEY, avaxProvider);
  const avaxCircleIntegration = ICircleIntegration__factory.connect(
    readCircleIntegrationProxyAddress(AVAX_FORK_CHAIN_ID),
    avaxWallet
  );

  // global
  const guardians = new MockGuardians(WORMHOLE_GUARDIAN_SET_INDEX, [
    GUARDIAN_PRIVATE_KEY,
  ]);

  describe("Registrations", () => {
    const governance = new CircleGovernanceEmitter();

    describe("Ethereum Goerli Testnet", () => {
      it("Register Foreign Circle Integration", async () => {
        const timestamp = getTimeNow();
        const chainId = await ethCircleIntegration.chainId();

        const emitterChain = await avaxCircleIntegration.chainId();
        const emitterAddress = Buffer.from(
          tryNativeToUint8Array(avaxCircleIntegration.address, "avalanche")
        );
        const domain = await avaxCircleIntegration.localDomain();

        const published =
          governance.publishCircleIntegrationRegisterEmitterAndDomain(
            timestamp,
            chainId,
            emitterChain,
            emitterAddress,
            domain
          );
        const signedMessage = guardians.addSignatures(published, [0]);

        const receipt = await ethCircleIntegration
          .registerEmitterAndDomain(signedMessage)
          .then((tx) => tx.wait())
          .catch((msg) => {
            // should not happen
            console.log(msg);
            return null;
          });
        expect(receipt).is.not.null;

        // check state
        const registeredEmitter = await ethCircleIntegration
          .getRegisteredEmitter(emitterChain)
          .then((bytes) => Buffer.from(ethers.utils.arrayify(bytes)));
        expect(Buffer.compare(registeredEmitter, emitterAddress)).to.equal(0);
      });

      it("Register Accepted Token", async () => {
        const timestamp = getTimeNow();
        const chainId = await ethCircleIntegration.chainId();

        const published =
          governance.publishCircleIntegrationRegisterAcceptedToken(
            timestamp,
            chainId,
            ETH_USDC_TOKEN_ADDRESS
          );
        const signedMessage = guardians.addSignatures(published, [0]);

        const receipt = await ethCircleIntegration
          .registerAcceptedToken(signedMessage)
          .then((tx) => tx.wait())
          .catch((msg) => {
            // should not happen
            console.log(msg);
            return null;
          });
        expect(receipt).is.not.null;

        // check state
        const accepted = await ethCircleIntegration.isAcceptedToken(
          ETH_USDC_TOKEN_ADDRESS
        );
        expect(accepted).is.true;
      });

      it("Register Target Chain Token", async () => {
        const timestamp = getTimeNow();
        const chainId = await ethCircleIntegration.chainId();

        const targetChain = await avaxCircleIntegration.chainId();
        const targetToken = Buffer.from(
          tryNativeToUint8Array(AVAX_USDC_TOKEN_ADDRESS, "avalanche")
        );

        const published =
          governance.publishCircleIntegrationRegisterTargetChainToken(
            timestamp,
            chainId,
            ETH_USDC_TOKEN_ADDRESS,
            targetChain,
            targetToken
          );
        const signedMessage = guardians.addSignatures(published, [0]);

        const receipt = await ethCircleIntegration
          .registerTargetChainToken(signedMessage)
          .then((tx) => tx.wait())
          .catch((msg) => {
            // should not happen
            console.log(msg);
            return null;
          });
        expect(receipt).is.not.null;

        // check state
        const registeredTargetToken = await ethCircleIntegration
          .targetAcceptedToken(ETH_USDC_TOKEN_ADDRESS, targetChain)
          .then((bytes) => Buffer.from(ethers.utils.arrayify(bytes)));
        expect(Buffer.compare(registeredTargetToken, targetToken)).to.equal(0);
      });
    });

    describe("Avalanche Fuji Testnet", () => {
      it("Register Foreign Circle Integration", async () => {
        const timestamp = getTimeNow();
        const chainId = await avaxCircleIntegration.chainId();

        const emitterChain = await ethCircleIntegration.chainId();
        const emitterAddress = Buffer.from(
          tryNativeToUint8Array(ethCircleIntegration.address, "avalanche")
        );
        const domain = await ethCircleIntegration.localDomain();

        const published =
          governance.publishCircleIntegrationRegisterEmitterAndDomain(
            timestamp,
            chainId,
            emitterChain,
            emitterAddress,
            domain
          );
        const signedMessage = guardians.addSignatures(published, [0]);

        const receipt = await avaxCircleIntegration
          .registerEmitterAndDomain(signedMessage)
          .then((tx) => tx.wait())
          .catch((msg) => {
            // should not happen
            console.log(msg);
            return null;
          });
        expect(receipt).is.not.null;

        // check state
        const registeredEmitter = await avaxCircleIntegration
          .getRegisteredEmitter(emitterChain)
          .then((bytes) => Buffer.from(ethers.utils.arrayify(bytes)));
        expect(Buffer.compare(registeredEmitter, emitterAddress)).to.equal(0);
      });

      it("Register Accepted Token", async () => {
        const timestamp = getTimeNow();
        const chainId = await avaxCircleIntegration.chainId();

        const published =
          governance.publishCircleIntegrationRegisterAcceptedToken(
            timestamp,
            chainId,
            AVAX_USDC_TOKEN_ADDRESS
          );
        const signedMessage = guardians.addSignatures(published, [0]);

        const receipt = await avaxCircleIntegration
          .registerAcceptedToken(signedMessage)
          .then((tx) => tx.wait())
          .catch((msg) => {
            // should not happen
            console.log(msg);
            return null;
          });
        expect(receipt).is.not.null;

        // check state
        const accepted = await avaxCircleIntegration.isAcceptedToken(
          AVAX_USDC_TOKEN_ADDRESS
        );
        expect(accepted).is.true;
      });

      it("Register Target Chain Token", async () => {
        const timestamp = getTimeNow();
        const chainId = await avaxCircleIntegration.chainId();

        const targetChain = await ethCircleIntegration.chainId();
        const targetToken = Buffer.from(
          tryNativeToUint8Array(ETH_USDC_TOKEN_ADDRESS, "avalanche")
        );

        const published =
          governance.publishCircleIntegrationRegisterTargetChainToken(
            timestamp,
            chainId,
            AVAX_USDC_TOKEN_ADDRESS,
            targetChain,
            targetToken
          );
        const signedMessage = guardians.addSignatures(published, [0]);

        const receipt = await avaxCircleIntegration
          .registerTargetChainToken(signedMessage)
          .then((tx) => tx.wait())
          .catch((msg) => {
            // should not happen
            console.log(msg);
            return null;
          });
        expect(receipt).is.not.null;

        // check state
        const registeredTargetToken = await avaxCircleIntegration
          .targetAcceptedToken(AVAX_USDC_TOKEN_ADDRESS, targetChain)
          .then((bytes) => Buffer.from(ethers.utils.arrayify(bytes)));
        expect(Buffer.compare(registeredTargetToken, targetToken)).to.equal(0);
      });
    });
  });

  describe("ETH -> AVAX", () => {
    it("transferWithPayload", async () => {
      // TODO
    });
  });

  describe("AVAX -> ETH", () => {
    it("redeemWithPayload", async () => {
      // TODO
    });
  });
});

function readCircleIntegrationProxyAddress(chain: number): string {
  return JSON.parse(
    fs.readFileSync(
      `${__dirname}/../../broadcast-test/deploy_contracts.sol/${chain}/run-latest.json`,
      "utf-8"
    )
  ).transactions[2].contractAddress;
}
