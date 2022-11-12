import { expect } from "chai";
import { ethers } from "ethers";
import {
  CHAIN_ID_AVAX,
  CHAIN_ID_ETH,
  tryNativeToUint8Array,
} from "@certusone/wormhole-sdk";
import {
  AVAX_USDC_TOKEN_ADDRESS,
  ETH_USDC_TOKEN_ADDRESS,
  GUARDIAN_PRIVATE_KEY,
  WORMHOLE_GUARDIAN_SET_INDEX,
  ETH_LOCALHOST,
  WALLET_PRIVATE_KEY,
  AVAX_LOCALHOST,
  ETH_FORK_CHAIN_ID,
  AVAX_FORK_CHAIN_ID,
} from "./helpers/consts";
import {
  ICircleIntegration__factory,
  IUSDC__factory,
} from "../src/ethers-contracts";
import { MockGuardians } from "@certusone/wormhole-sdk/lib/cjs/mock";
import { RedeemParameters, TransferParameters } from "../src";
import { findCircleMessageInLogs } from "../src/logs";

import { CircleGovernanceEmitter } from "./helpers/mock";
import {
  getTimeNow,
  MockCircleAttester,
  readCircleIntegrationProxyAddress,
  findWormholeMessageInLogs,
} from "./helpers/utils";

describe("Circle Integration Test", () => {
  // ethereum
  const ethProvider = new ethers.providers.StaticJsonRpcProvider(ETH_LOCALHOST);
  const ethWallet = new ethers.Wallet(WALLET_PRIVATE_KEY, ethProvider);
  const ethCircleIntegration = ICircleIntegration__factory.connect(
    readCircleIntegrationProxyAddress(ETH_FORK_CHAIN_ID),
    ethWallet
  );
  const ethUsdc = IUSDC__factory.connect(ETH_USDC_TOKEN_ADDRESS, ethWallet);

  // avalanche
  const avaxProvider = new ethers.providers.StaticJsonRpcProvider(
    AVAX_LOCALHOST
  );
  const avaxWallet = new ethers.Wallet(WALLET_PRIVATE_KEY, avaxProvider);
  const avaxCircleIntegration = ICircleIntegration__factory.connect(
    readCircleIntegrationProxyAddress(AVAX_FORK_CHAIN_ID),
    avaxWallet
  );
  const avaxUsdc = IUSDC__factory.connect(AVAX_USDC_TOKEN_ADDRESS, avaxWallet);

  // global
  const guardians = new MockGuardians(WORMHOLE_GUARDIAN_SET_INDEX, [
    GUARDIAN_PRIVATE_KEY,
  ]);
  const circleAttester = new MockCircleAttester(GUARDIAN_PRIVATE_KEY);

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
    const amount = ethers.BigNumber.from("69");

    let localVariables: any = {};

    it("transferWithPayload", async () => {
      const params: TransferParameters = {
        token: ETH_USDC_TOKEN_ADDRESS,
        amount,
        targetChain: CHAIN_ID_AVAX as number,
        mintRecipient: tryNativeToUint8Array(ethWallet.address, "avalanche"),
      };
      const batchId = 0;
      const payload = Buffer.from("All your base are belong to us.");

      // increase allowance
      {
        const receipt = await ethUsdc
          .approve(ethCircleIntegration.address, amount)
          .then((tx) => tx.wait());
      }

      const balanceBefore = await ethUsdc.balanceOf(ethWallet.address);

      const receipt = await ethCircleIntegration
        .transferTokensWithPayload(params, batchId, payload)
        .then(async (tx) => {
          const receipt = await tx.wait();
          return receipt;
        })
        .catch((msg) => {
          // should not happen
          console.log(msg);
          return null;
        });
      expect(receipt).is.not.null;

      const balanceAfter = await ethUsdc.balanceOf(ethWallet.address);
      expect(balanceBefore.sub(balanceAfter).eq(amount)).is.true;

      // Grab Circle message from logs
      const circleMessage = await ethCircleIntegration
        .circleTransmitter()
        .then((address) => findCircleMessageInLogs(receipt!.logs, address));
      expect(circleMessage).is.not.null;

      // Grab attestation
      const circleAttestation = circleAttester.attestMessage(
        ethers.utils.arrayify(circleMessage!)
      );

      // Now grab the Wormhole Message
      const wormholeMessage = await ethCircleIntegration
        .wormhole()
        .then((address) =>
          findWormholeMessageInLogs(
            receipt!.logs,
            address,
            CHAIN_ID_ETH as number
          )
        );
      expect(wormholeMessage).is.not.null;

      const encodedWormholeMessage = Uint8Array.from(
        guardians.addSignatures(wormholeMessage!, [0])
      );

      localVariables.circleBridgeMessage = circleMessage!;
      localVariables.circleAttestation = circleAttestation!;
      localVariables.encodedWormholeMessage = encodedWormholeMessage;
    });

    it("redeemWithPayload", async () => {
      const redeemParameters: RedeemParameters = {
        circleBridgeMessage: localVariables.circleBridgeMessage!,
        circleAttestation: localVariables.circleAttestation!,
        encodedWormholeMessage: localVariables.encodedWormholeMessage!,
      };

      const balanceBefore = await avaxUsdc.balanceOf(avaxWallet.address);

      const receipt = await avaxCircleIntegration
        .redeemTokensWithPayload(redeemParameters)
        .then(async (tx) => {
          const receipt = await tx.wait();
          return receipt;
        })
        .catch((msg) => {
          // should not happen
          console.log(msg);
          return null;
        });
      expect(receipt).is.not.null;

      const balanceAfter = await avaxUsdc.balanceOf(avaxWallet.address);
      expect(balanceAfter.sub(balanceBefore).eq(amount)).is.true;
    });
  });

  describe("AVAX -> ETH", () => {
    it("transferWithPayload", async () => {
      // TODO
    });

    it("redeemWithPayload", async () => {
      // TODO
    });
  });
});
