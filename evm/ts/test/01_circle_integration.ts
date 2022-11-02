import { expect } from "chai";
import { ethers } from "ethers";
import { tryNativeToHexString } from "@certusone/wormhole-sdk";
import {
  AVAX_USDC_TOKEN_ADDRESS,
  CIRCLE_INTEGRATION_ADDRESS,
  FORK_CHAIN_ID,
  GUARDIAN_PRIVATE_KEY,
  GUARDIAN_SET_INDEX,
  LOCALHOST,
  WALLET_PRIVATE_KEY,
  WORMHOLE_ADDRESS,
  WORMHOLE_CHAIN_ID,
  WORMHOLE_GUARDIAN_SET_INDEX,
  WORMHOLE_MESSAGE_FEE,
} from "./helpers/consts";
import {
  IWormhole__factory,
  ICircleIntegration__factory,
} from "../src/ethers-contracts";
import { MockGuardians } from "@certusone/wormhole-sdk/lib/cjs/mock";
import { MockCircleIntegration, CircleGovernanceEmitter } from "./helpers/mock";
import { getBlockTimestamp } from "./helpers/utils";

describe("Circle Integration Test", () => {
  const provider = new ethers.providers.StaticJsonRpcProvider(LOCALHOST);
  const wallet = new ethers.Wallet(WALLET_PRIVATE_KEY, provider);

  const wormhole = IWormhole__factory.connect(WORMHOLE_ADDRESS, provider);
  const circleIntegration = ICircleIntegration__factory.connect(
    CIRCLE_INTEGRATION_ADDRESS,
    wallet
  );

  const guardians = new MockGuardians(GUARDIAN_SET_INDEX, [
    GUARDIAN_PRIVATE_KEY,
  ]);

  const foreignCircleIntegration = new MockCircleIntegration(
    CIRCLE_INTEGRATION_ADDRESS,
    6, // chainId
    1, // domain
    circleIntegration
  );

  describe("Circle Integration Registrations", () => {
    const governance = new CircleGovernanceEmitter();

    it("Register Foreign Circle Integration", async () => {
      const timestamp = await getBlockTimestamp(provider);
      const chainId = await circleIntegration.chainId();

      const published =
        governance.publishCircleIntegrationRegisterEmitterAndDomain(
          timestamp,
          chainId,
          foreignCircleIntegration.chain,
          foreignCircleIntegration.address,
          foreignCircleIntegration.domain
        );
      const signedMessage = guardians.addSignatures(published, [0]);

      const receipt = await circleIntegration
        .registerEmitterAndDomain(signedMessage)
        .then((tx) => tx.wait())
        .catch((msg) => {
          // should not happen
          console.log(msg.error.reason);
          return null;
        });
      expect(receipt).is.not.null;
    });

    it("Register Accepted Token", async () => {
      const timestamp = await getBlockTimestamp(provider);
      const chainId = await circleIntegration.chainId();

      const published =
        governance.publishCircleIntegrationRegisterAcceptedToken(
          timestamp,
          chainId,
          AVAX_USDC_TOKEN_ADDRESS
        );
      const signedMessage = guardians.addSignatures(published, [0]);

      const receipt = await circleIntegration
        .registerAcceptedToken(signedMessage)
        .then((tx) => tx.wait())
        .catch((msg) => {
          // should not happen
          console.log(msg.error.reason);
          return null;
        });
      expect(receipt).is.not.null;
    });

    it("Register Target Chain Token", async () => {
      // TODO
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
