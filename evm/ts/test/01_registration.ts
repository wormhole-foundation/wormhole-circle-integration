import {expect} from "chai";
import {ethers} from "ethers";
import {
  CHAIN_ID_ALGORAND,
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
  WALLET_PRIVATE_KEY_TWO,
  AVAX_LOCALHOST,
  ETH_FORK_CHAIN_ID,
  AVAX_FORK_CHAIN_ID,
  ETH_WORMHOLE_ADDRESS,
  AVAX_WORMHOLE_ADDRESS,
} from "./helpers/consts";
import {
  ICircleIntegration__factory,
  IUSDC__factory,
  IMockIntegration__factory,
  IWormhole__factory,
} from "../src/ethers-contracts";
import {MockGuardians} from "@certusone/wormhole-sdk/lib/cjs/mock";
import {RedeemParameters, TransferParameters} from "../src";
import {findCircleMessageInLogs} from "../src/logs";

import {CircleGovernanceEmitter} from "./helpers/mock";
import {
  getTimeNow,
  MockCircleAttester,
  readCircleIntegrationProxyAddress,
  readMockIntegrationAddress,
  findWormholeMessageInLogs,
  findRedeemEventInLogs,
} from "./helpers/utils";

describe("Circle Integration Registration", () => {
  // ethereum wallet, CircleIntegration contract and USDC contract
  const ethProvider = new ethers.providers.StaticJsonRpcProvider(ETH_LOCALHOST);
  const ethWallet = new ethers.Wallet(WALLET_PRIVATE_KEY, ethProvider);
  const ethCircleIntegration = ICircleIntegration__factory.connect(
    readCircleIntegrationProxyAddress(ETH_FORK_CHAIN_ID),
    ethWallet
  );
  const ethUsdc = IUSDC__factory.connect(ETH_USDC_TOKEN_ADDRESS, ethWallet);

  // avalanche wallet, CircleIntegration contract and USDC contract
  const avaxProvider = new ethers.providers.StaticJsonRpcProvider(
    AVAX_LOCALHOST
  );
  const avaxWallet = new ethers.Wallet(WALLET_PRIVATE_KEY, avaxProvider);
  const avaxCircleIntegration = ICircleIntegration__factory.connect(
    readCircleIntegrationProxyAddress(AVAX_FORK_CHAIN_ID),
    avaxWallet
  );
  const avaxUsdc = IUSDC__factory.connect(AVAX_USDC_TOKEN_ADDRESS, avaxWallet);

  // mock integration contract on avax
  const avaxMockIntegration = IMockIntegration__factory.connect(
    readMockIntegrationAddress(AVAX_FORK_CHAIN_ID),
    avaxWallet
  );

  // MockGuardians and MockCircleAttester objects
  const guardians = new MockGuardians(WORMHOLE_GUARDIAN_SET_INDEX, [
    GUARDIAN_PRIVATE_KEY,
  ]);
  const circleAttester = new MockCircleAttester(GUARDIAN_PRIVATE_KEY);

  // Wormhole contracts
  const ethWormhole = IWormhole__factory.connect(
    ETH_WORMHOLE_ADDRESS,
    ethWallet
  );
  const avaxWormhole = IWormhole__factory.connect(
    AVAX_WORMHOLE_ADDRESS,
    avaxWallet
  );

  describe("Registrations", () => {
    // produces governance VAAs for CircleAttestation contract
    const governance = new CircleGovernanceEmitter();

    describe("Ethereum Goerli Testnet", () => {
      it("Should Register Foreign Circle Integration", async () => {
        const timestamp = getTimeNow();
        const chainId = await ethCircleIntegration.chainId();
        const emitterChain = await avaxCircleIntegration.chainId();
        const emitterAddress = Buffer.from(
          tryNativeToUint8Array(avaxCircleIntegration.address, "avalanche")
        );
        const domain = await avaxCircleIntegration.localDomain();

        // create unsigned registerEmitterAndDomain governance message
        const published =
          governance.publishCircleIntegrationRegisterEmitterAndDomain(
            timestamp,
            chainId,
            emitterChain,
            emitterAddress,
            domain
          );

        // sign governance message with guardian key
        const signedMessage = guardians.addSignatures(published, [0]);

        // register the emitter and domain
        const receipt = await ethCircleIntegration
          .registerEmitterAndDomain(signedMessage)
          .then((tx) => tx.wait())
          .catch((msg) => {
            // should not happen
            console.log(msg);
            return null;
          });
        expect(receipt).is.not.null;

        // check contract state to verify the registration
        const registeredEmitter = await ethCircleIntegration
          .getRegisteredEmitter(emitterChain)
          .then((bytes) => Buffer.from(ethers.utils.arrayify(bytes)));
        expect(Buffer.compare(registeredEmitter, emitterAddress)).to.equal(0);
      });

      it("Should Register Accepted Token", async () => {
        const timestamp = getTimeNow();
        const chainId = await ethCircleIntegration.chainId();

        // create unsigned registerAcceptedToken governance message
        const published =
          governance.publishCircleIntegrationRegisterAcceptedToken(
            timestamp,
            chainId,
            ETH_USDC_TOKEN_ADDRESS
          );

        // sign governance message with guardian key
        const signedMessage = guardians.addSignatures(published, [0]);

        // register the token
        const receipt = await ethCircleIntegration
          .registerAcceptedToken(signedMessage)
          .then((tx) => tx.wait())
          .catch((msg) => {
            // should not happen
            console.log(msg);
            return null;
          });
        expect(receipt).is.not.null;

        // check contract state to verify the registration
        const accepted = await ethCircleIntegration.isAcceptedToken(
          ETH_USDC_TOKEN_ADDRESS
        );
        expect(accepted).is.true;
      });
    });

    describe("Avalanche Fuji Testnet", () => {
      it("Should Register Foreign Circle Integration", async () => {
        const timestamp = getTimeNow();
        const chainId = await avaxCircleIntegration.chainId();
        const emitterChain = await ethCircleIntegration.chainId();
        const emitterAddress = Buffer.from(
          tryNativeToUint8Array(ethCircleIntegration.address, "avalanche")
        );
        const domain = await ethCircleIntegration.localDomain();

        // create unsigned registerEmitterAndDomain governance message
        const published =
          governance.publishCircleIntegrationRegisterEmitterAndDomain(
            timestamp,
            chainId,
            emitterChain,
            emitterAddress,
            domain
          );
        const signedMessage = guardians.addSignatures(published, [0]);

        // sign governance message with guardian key
        const receipt = await avaxCircleIntegration
          .registerEmitterAndDomain(signedMessage)
          .then((tx) => tx.wait())
          .catch((msg) => {
            // should not happen
            console.log(msg);
            return null;
          });
        expect(receipt).is.not.null;

        // check contract state to verify the registration
        const registeredEmitter = await avaxCircleIntegration
          .getRegisteredEmitter(emitterChain)
          .then((bytes) => Buffer.from(ethers.utils.arrayify(bytes)));
        expect(Buffer.compare(registeredEmitter, emitterAddress)).to.equal(0);
      });

      it("Should Register Accepted Token", async () => {
        const timestamp = getTimeNow();
        const chainId = await avaxCircleIntegration.chainId();

        // create unsigned registerAcceptedToken governance message
        const published =
          governance.publishCircleIntegrationRegisterAcceptedToken(
            timestamp,
            chainId,
            AVAX_USDC_TOKEN_ADDRESS
          );

        // sign governance message with guardian key
        const signedMessage = guardians.addSignatures(published, [0]);

        // register the token
        const receipt = await avaxCircleIntegration
          .registerAcceptedToken(signedMessage)
          .then((tx) => tx.wait())
          .catch((msg) => {
            // should not happen
            console.log(msg);
            return null;
          });
        expect(receipt).is.not.null;

        // check contract state to verify the registration
        const accepted = await avaxCircleIntegration.isAcceptedToken(
          AVAX_USDC_TOKEN_ADDRESS
        );
        expect(accepted).is.true;
      });
    });
  });
});
