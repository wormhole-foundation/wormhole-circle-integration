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

describe("Circle Integration Registration", () => {
  // ethereum wallet, CircleIntegration contract and USDC contract
  const ethProvider = new ethers.providers.StaticJsonRpcProvider(ETH_LOCALHOST);
  const ethWallet = new ethers.Wallet(WALLET_PRIVATE_KEY, ethProvider);
  const ethCircleIntegration = ICircleIntegration__factory.connect(
    readCircleIntegrationProxyAddress(ETH_FORK_CHAIN_ID),
    ethWallet
  );

  // avalanche wallet, CircleIntegration contract and USDC contract
  const avaxProvider = new ethers.providers.StaticJsonRpcProvider(
    AVAX_LOCALHOST
  );
  const avaxWallet = new ethers.Wallet(WALLET_PRIVATE_KEY, avaxProvider);
  const avaxCircleIntegration = ICircleIntegration__factory.connect(
    readCircleIntegrationProxyAddress(AVAX_FORK_CHAIN_ID),
    avaxWallet
  );

  // MockGuardians and MockCircleAttester objects
  const guardians = new MockGuardians(WORMHOLE_GUARDIAN_SET_INDEX, [
    GUARDIAN_PRIVATE_KEY,
  ]);

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
    });
  });
});
