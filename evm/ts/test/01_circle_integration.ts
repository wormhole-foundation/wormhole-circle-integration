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
} from "./helpers/consts";
import {
  ICircleIntegration__factory,
  IUSDC__factory,
} from "../src/ethers-contracts";
import {MockGuardians} from "@certusone/wormhole-sdk/lib/cjs/mock";
import {RedeemParameters, TransferParameters} from "../src";
import {findCircleMessageInLogs} from "../src/logs";

import {CircleGovernanceEmitter} from "./helpers/mock";
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
      it("Should Register Foreign Circle Integration", async () => {
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

      it("Should Register Accepted Token", async () => {
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

      it("Should Register Target Chain Token", async () => {
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
      it("Should Register Foreign Circle Integration", async () => {
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

      it("Should Register Accepted Token", async () => {
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

      it("Should Register Target Chain Token", async () => {
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

  describe("Transfer With Payload Logic", () => {
    const amountFromEth = ethers.BigNumber.from("69");
    const amountFromAvax = ethers.BigNumber.from("420");

    let localVariables: any = {};

    it("Should Transfer Tokens With Payload On Ethereum", async () => {
      // define transferTokensWithPayload function arguments
      const params: TransferParameters = {
        token: ETH_USDC_TOKEN_ADDRESS,
        amount: amountFromEth,
        targetChain: CHAIN_ID_AVAX as number,
        mintRecipient: tryNativeToUint8Array(ethWallet.address, "avalanche"),
      };
      const batchId = 0; // opt out of batching
      const payload = Buffer.from("All your base are belong to us.");

      // increase allowance
      {
        const receipt = await ethUsdc
          .approve(ethCircleIntegration.address, amountFromEth)
          .then((tx) => tx.wait());
      }

      // grab USDC balance before performing the transfer
      const balanceBefore = await ethUsdc.balanceOf(ethWallet.address);

      // call transferTokensWithPayload
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

      // check USDC balance after to confirm the transfer worked
      const balanceAfter = await ethUsdc.balanceOf(ethWallet.address);
      expect(balanceBefore.sub(balanceAfter).eq(amountFromEth)).is.true;

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

    it("Should Redeem Tokens With Payload On Avax", async () => {
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

      // save all of the redeem parameters
      const balanceAfter = await avaxUsdc.balanceOf(avaxWallet.address);
      expect(balanceAfter.sub(balanceBefore).eq(amountFromEth)).is.true;
    });

    it("Should Transfer Tokens With Payload On Avax", async () => {
      // define transferTokensWithPayload function arguments
      const params: TransferParameters = {
        token: AVAX_USDC_TOKEN_ADDRESS,
        amount: amountFromAvax,
        targetChain: CHAIN_ID_ETH as number,
        mintRecipient: tryNativeToUint8Array(avaxWallet.address, "ethereum"),
      };
      const batchId = 0; // opt out of batching
      const payload = Buffer.from("Send me back to Ethereum!");

      // increase allowance
      {
        const receipt = await avaxUsdc
          .approve(avaxCircleIntegration.address, amountFromAvax)
          .then((tx) => tx.wait());
      }

      // grab USDC balance before performing the transfer
      const balanceBefore = await avaxUsdc.balanceOf(avaxWallet.address);

      // call transferTokensWithPayload
      const receipt = await avaxCircleIntegration
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

      // check USDC balance after to confirm the transfer worked
      const balanceAfter = await avaxUsdc.balanceOf(avaxWallet.address);
      expect(balanceBefore.sub(balanceAfter).eq(amountFromAvax)).is.true;

      // Grab Circle message from logs
      const circleMessage = await avaxCircleIntegration
        .circleTransmitter()
        .then((address) => findCircleMessageInLogs(receipt!.logs, address));
      expect(circleMessage).is.not.null;

      // Grab attestation
      const circleAttestation = circleAttester.attestMessage(
        ethers.utils.arrayify(circleMessage!)
      );

      // Now grab the Wormhole Message
      const wormholeMessage = await avaxCircleIntegration
        .wormhole()
        .then((address) =>
          findWormholeMessageInLogs(
            receipt!.logs,
            address,
            CHAIN_ID_AVAX as number
          )
        );
      expect(wormholeMessage).is.not.null;

      const encodedWormholeMessage = Uint8Array.from(
        guardians.addSignatures(wormholeMessage!, [0])
      );

      // save all of the redeem parameters
      localVariables.circleBridgeMessage = circleMessage!;
      localVariables.circleAttestation = circleAttestation!;
      localVariables.encodedWormholeMessage = encodedWormholeMessage;
    });

    it("Should Redeem Tokens With Payload On Ethereum", async () => {
      const redeemParameters: RedeemParameters = {
        circleBridgeMessage: localVariables.circleBridgeMessage!,
        circleAttestation: localVariables.circleAttestation!,
        encodedWormholeMessage: localVariables.encodedWormholeMessage!,
      };

      const balanceBefore = await ethUsdc.balanceOf(ethWallet.address);

      const receipt = await ethCircleIntegration
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

      // save all of the redeem parameters
      const balanceAfter = await ethUsdc.balanceOf(avaxWallet.address);
      expect(balanceAfter.sub(balanceBefore).eq(amountFromAvax)).is.true;
    });

    it("Should Not Redeem a Transfer More Than Once", async () => {
      const redeemParameters: RedeemParameters = {
        circleBridgeMessage: localVariables.circleBridgeMessage!,
        circleAttestation: localVariables.circleAttestation!,
        encodedWormholeMessage: localVariables.encodedWormholeMessage!,
      };

      // balance before calling redeemTokensWithPayload
      const balanceBefore = await ethUsdc.balanceOf(ethWallet.address);

      // try to submit a new guardian set including the zero address
      let failed: boolean = false;
      try {
        const receipt = await ethCircleIntegration
          .redeemTokensWithPayload(redeemParameters)
          .then(async (tx) => {
            const receipt = await tx.wait();
            return receipt;
          });
        expect(receipt).is.not.null;
      } catch (e: any) {
        expect(e.error.reason, "execution reverted: message already consumed")
          .to.be.equal;
        failed = true;
      }

      // confirm that the call failed
      expect(failed).is.true;

      // save all of the redeem parameters
      const balanceAfter = await ethUsdc.balanceOf(avaxWallet.address);
      expect(balanceAfter.eq(balanceBefore)).is.true;
    });

    it("Should Not Allow Transfers for Zero Amount", async () => {
      // define transferTokensWithPayload function arguments
      const params: TransferParameters = {
        token: avaxWallet.address,
        amount: ethers.BigNumber.from("0"), // zero amount
        targetChain: CHAIN_ID_ETH as number,
        mintRecipient: tryNativeToUint8Array(avaxWallet.address, "ethereum"),
      };
      const batchId = 0; // opt out of batching
      const payload = Buffer.from("Send with amount of zero :)");

      // try to submit a new guardian set including the zero address
      let failed: boolean = false;
      try {
        // call transferTokensWithPayload
        const receipt = await avaxCircleIntegration
          .transferTokensWithPayload(params, batchId, payload)
          .then(async (tx) => {
            const receipt = await tx.wait();
            return receipt;
          });
      } catch (e: any) {
        expect(e.error.reason, "execution reverted: amount must be > 0").to.be
          .equal;
        failed = true;
      }

      // confirm that the call failed
      expect(failed).is.true;
    });

    it("Should Not Allow Transfers to the Zero Address", async () => {
      // define transferTokensWithPayload function arguments
      const params: TransferParameters = {
        token: avaxWallet.address,
        amount: amountFromAvax,
        targetChain: CHAIN_ID_ETH as number,
        mintRecipient: tryNativeToUint8Array("0x", "ethereum"), // zero address
      };
      const batchId = 0; // opt out of batching
      const payload = Buffer.from("Sending to bytes32(0) mintRecipient :)");

      // try to submit a new guardian set including the zero address
      let failed: boolean = false;
      try {
        // call transferTokensWithPayload
        const receipt = await avaxCircleIntegration
          .transferTokensWithPayload(params, batchId, payload)
          .then(async (tx) => {
            const receipt = await tx.wait();
            return receipt;
          });
      } catch (e: any) {
        expect(e.error.reason, "execution reverted: invalid mint recipient").to
          .be.equal;
        failed = true;
      }

      // confirm that the call failed
      expect(failed).is.true;
    });

    it("Should Not Allow Transfers for Unregistered Tokens", async () => {
      // define transferTokensWithPayload function arguments
      const params: TransferParameters = {
        token: avaxWallet.address, // unregistered "token"
        amount: amountFromAvax,
        targetChain: CHAIN_ID_ETH as number,
        mintRecipient: tryNativeToUint8Array(avaxWallet.address, "ethereum"),
      };
      const batchId = 0; // opt out of batching
      const payload = Buffer.from("Sending an unregistered token :)");

      // try to submit a new guardian set including the zero address
      let failed: boolean = false;
      try {
        // call transferTokensWithPayload
        const receipt = await avaxCircleIntegration
          .transferTokensWithPayload(params, batchId, payload)
          .then(async (tx) => {
            const receipt = await tx.wait();
            return receipt;
          });
      } catch (e: any) {
        expect(e.error.reason, "execution reverted: token not accepted").to.be
          .equal;
        failed = true;
      }

      // confirm that the call failed
      expect(failed).is.true;
    });

    it("Should Not Allow Transfers to Unregistered Contracts", async () => {
      // define transferTokensWithPayload function arguments
      const params: TransferParameters = {
        token: avaxWallet.address,
        amount: amountFromAvax,
        targetChain: CHAIN_ID_ALGORAND as number, // unregistered chain
        mintRecipient: tryNativeToUint8Array(avaxWallet.address, "ethereum"),
      };
      const batchId = 0; // opt out of batching
      const payload = Buffer.from("Sending to an unregistered chain :)");

      // try to submit a new guardian set including the zero address
      let failed: boolean = false;
      try {
        // call transferTokensWithPayload
        const receipt = await avaxCircleIntegration
          .transferTokensWithPayload(params, batchId, payload)
          .then(async (tx) => {
            const receipt = await tx.wait();
            return receipt;
          });
      } catch (e: any) {
        expect(
          e.error.reason,
          "execution reverted: target contract not registered"
        ).to.be.equal;
        failed = true;
      }

      // confirm that the call failed
      expect(failed).is.true;
    });

    it("Should Not Allow Transfers for Unregistered Target Tokens", async () => {
      // initialize governance module
      const governance = new CircleGovernanceEmitter();

      // store euroc address
      const eurocAddress = "0x53d80871b92dadeD34A4BdFA6838DdFC7f214240";
      const timestamp = getTimeNow();
      const chainId = await avaxCircleIntegration.chainId();

      const published =
        governance.publishCircleIntegrationRegisterAcceptedToken(
          timestamp,
          chainId,
          eurocAddress
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
        eurocAddress
      );
      expect(accepted).is.true;

      // define transferTokensWithPayload function arguments
      const params: TransferParameters = {
        token: eurocAddress,
        amount: amountFromAvax,
        targetChain: CHAIN_ID_ALGORAND as number, // unregistered chain
        mintRecipient: tryNativeToUint8Array(avaxWallet.address, "ethereum"),
      };
      const batchId = 0; // opt out of batching
      const payload = Buffer.from("Sending an unregistered target token :)");

      // try to submit a new guardian set including the zero address
      let failed: boolean = false;
      try {
        // call transferTokensWithPayload
        const receipt = await avaxCircleIntegration
          .transferTokensWithPayload(params, batchId, payload)
          .then(async (tx) => {
            const receipt = await tx.wait();
            return receipt;
          });
      } catch (e: any) {
        expect(
          e.error.reason,
          "execution reverted: target token not registered"
        ).to.be.equal;
        failed = true;
      }

      // confirm that the call failed
      expect(failed).is.true;
    });

    it("Should Only Mint Tokens to the Mint Recipient", async () => {
      // define transferTokensWithPayload function arguments
      const params: TransferParameters = {
        token: AVAX_USDC_TOKEN_ADDRESS,
        amount: amountFromAvax,
        targetChain: CHAIN_ID_ETH as number,
        mintRecipient: tryNativeToUint8Array(avaxWallet.address, "ethereum"),
      };
      const batchId = 0; // opt out of batching
      const payload = Buffer.from("Send me back to Ethereum!");

      // increase allowance
      const receipt = await avaxUsdc
        .approve(avaxCircleIntegration.address, amountFromAvax)
        .then((tx) => tx.wait());

      // call transfer with payload and save redeemParameters struct
      let redeemParameters = {} as RedeemParameters;
      {
        // grab USDC balance before performing the transfer
        const balanceBefore = await avaxUsdc.balanceOf(avaxWallet.address);

        // call transferTokensWithPayload
        const receipt = await avaxCircleIntegration
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

        // check USDC balance after to confirm the transfer worked
        const balanceAfter = await avaxUsdc.balanceOf(avaxWallet.address);
        expect(balanceBefore.sub(balanceAfter).eq(amountFromAvax)).is.true;

        // Grab Circle message from logs
        const circleMessage = await avaxCircleIntegration
          .circleTransmitter()
          .then((address) => findCircleMessageInLogs(receipt!.logs, address));
        expect(circleMessage).is.not.null;

        // Grab attestation
        const circleAttestation = circleAttester.attestMessage(
          ethers.utils.arrayify(circleMessage!)
        );

        // Now grab the Wormhole Message
        const wormholeMessage = await avaxCircleIntegration
          .wormhole()
          .then((address) =>
            findWormholeMessageInLogs(
              receipt!.logs,
              address,
              CHAIN_ID_AVAX as number
            )
          );
        expect(wormholeMessage).is.not.null;

        const encodedWormholeMessage = Uint8Array.from(
          guardians.addSignatures(wormholeMessage!, [0])
        );

        // save redeemParameters struct
        redeemParameters = {
          circleBridgeMessage: ethers.utils.arrayify(circleMessage!),
          circleAttestation: circleAttestation!,
          encodedWormholeMessage: encodedWormholeMessage!,
        };
      }

      // try to redeem the transfer from a different wallet
      {
        // create wallet with different private key
        const invalidEthWallet = new ethers.Wallet(
          WALLET_PRIVATE_KEY_TWO,
          ethProvider
        );

        // connect to contract with invalid wallet for redemption
        const ethCircleIntegration = ICircleIntegration__factory.connect(
          readCircleIntegrationProxyAddress(ETH_FORK_CHAIN_ID),
          invalidEthWallet
        );

        let failed: boolean = false;
        try {
          // call redeemTokensWithPayload
          const receipt = await ethCircleIntegration
            .redeemTokensWithPayload(redeemParameters)
            .then(async (tx) => {
              const receipt = await tx.wait();
              return receipt;
            });
        } catch (e: any) {
          expect(
            e.error.reason,
            "execution reverted: caller must be mintRecipient"
          ).to.be.equal;
          failed = true;
        }

        // confirm that the call failed
        expect(failed).is.true;
      }
    });

    it("Should Not Redeem Tokens With a Bad Message Pair", async () => {
      // define transferTokensWithPayload function arguments
      const params: TransferParameters = {
        token: AVAX_USDC_TOKEN_ADDRESS,
        amount: amountFromAvax,
        targetChain: CHAIN_ID_ETH as number,
        mintRecipient: tryNativeToUint8Array(avaxWallet.address, "ethereum"),
      };
      const batchId = 0; // opt out of batching
      const payload = Buffer.from("Send me back to Ethereum!");

      // increase the token allowance by 2x, since we will do two transfers
      const receipt = await avaxUsdc
        .approve(avaxCircleIntegration.address, amountFromAvax.mul(2))
        .then((tx) => tx.wait());

      // send the same transfer twice and save the redeemParameters
      let redeemParameters = {} as RedeemParameters[];
      {
        for (let i = 0; i < 2; i++) {
          // grab USDC balance before performing the transfer
          const balanceBefore = await avaxUsdc.balanceOf(avaxWallet.address);

          // call transferTokensWithPayload
          const receipt = await avaxCircleIntegration
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

          // check USDC balance after to confirm the transfer worked
          const balanceAfter = await avaxUsdc.balanceOf(avaxWallet.address);
          expect(balanceBefore.sub(balanceAfter).eq(amountFromAvax)).is.true;

          // Grab Circle message from logs
          const circleMessage = await avaxCircleIntegration
            .circleTransmitter()
            .then((address) => findCircleMessageInLogs(receipt!.logs, address));
          expect(circleMessage).is.not.null;

          // Grab attestation
          const circleAttestation = circleAttester.attestMessage(
            ethers.utils.arrayify(circleMessage!)
          );

          // Now grab the Wormhole Message
          const wormholeMessage = await avaxCircleIntegration
            .wormhole()
            .then((address) =>
              findWormholeMessageInLogs(
                receipt!.logs,
                address,
                CHAIN_ID_AVAX as number
              )
            );
          expect(wormholeMessage).is.not.null;

          const encodedWormholeMessage = Uint8Array.from(
            guardians.addSignatures(wormholeMessage!, [0])
          );

          // save redeemParameters struct
          redeemParameters[i] = {
            circleBridgeMessage: ethers.utils.arrayify(circleMessage!),
            circleAttestation: circleAttestation!,
            encodedWormholeMessage: encodedWormholeMessage!,
          };
        }
      }

      // Create new redeemParameters with an invalid message pair, by
      // pairing the Wormhole message from the second transfer with
      // the Circle message and attestation from the first transfer.
      const invalidRedeemParameters: RedeemParameters = {
        circleBridgeMessage: redeemParameters[0].circleBridgeMessage,
        circleAttestation: redeemParameters[0].circleAttestation,
        encodedWormholeMessage: redeemParameters[1].encodedWormholeMessage,
      };

      {
        let failed: boolean = false;
        try {
          // call redeemTokensWithPayload
          const receipt = await ethCircleIntegration
            .redeemTokensWithPayload(invalidRedeemParameters)
            .then(async (tx) => {
              const receipt = await tx.wait();
              return receipt;
            });
        } catch (e: any) {
          expect(e.error.reason, "execution reverted: invalid message pair").to
            .be.equal;
          failed = true;
        }

        // confirm that the call failed
        expect(failed).is.true;
      }
    });

    it("Should Revert if Circle Receiver Call Fails", async () => {
      // define transferTokensWithPayload function arguments
      const params: TransferParameters = {
        token: AVAX_USDC_TOKEN_ADDRESS,
        amount: amountFromAvax,
        targetChain: CHAIN_ID_ETH as number,
        mintRecipient: tryNativeToUint8Array(avaxWallet.address, "ethereum"),
      };
      const batchId = 0; // opt out of batching
      const payload = Buffer.from("Send me back to Ethereum!");

      // increase allowance
      const receipt = await avaxUsdc
        .approve(avaxCircleIntegration.address, amountFromAvax)
        .then((tx) => tx.wait());

      // call transfer with payload and save redeemParameters struct
      let redeemParameters = {} as RedeemParameters;
      {
        // grab USDC balance before performing the transfer
        const balanceBefore = await avaxUsdc.balanceOf(avaxWallet.address);

        // call transferTokensWithPayload
        const receipt = await avaxCircleIntegration
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

        // check USDC balance after to confirm the transfer worked
        const balanceAfter = await avaxUsdc.balanceOf(avaxWallet.address);
        expect(balanceBefore.sub(balanceAfter).eq(amountFromAvax)).is.true;

        // Grab Circle message from logs
        const circleMessage = await avaxCircleIntegration
          .circleTransmitter()
          .then((address) => findCircleMessageInLogs(receipt!.logs, address));
        expect(circleMessage).is.not.null;

        // Grab attestation
        const circleAttestation = circleAttester.attestMessage(
          ethers.utils.arrayify(circleMessage!)
        );

        // Now grab the Wormhole Message
        const wormholeMessage = await avaxCircleIntegration
          .wormhole()
          .then((address) =>
            findWormholeMessageInLogs(
              receipt!.logs,
              address,
              CHAIN_ID_AVAX as number
            )
          );
        expect(wormholeMessage).is.not.null;

        const encodedWormholeMessage = Uint8Array.from(
          guardians.addSignatures(wormholeMessage!, [0])
        );

        // save redeemParameters struct
        redeemParameters = {
          circleBridgeMessage: ethers.utils.arrayify(circleMessage!),
          circleAttestation: ethers.utils.arrayify("0x"),
          encodedWormholeMessage: encodedWormholeMessage!,
        };
      }

      // try to redeem the transfer from a different wallet
      {
        let failed: boolean = false;
        try {
          // call redeemTokensWithPayload
          const receipt = await ethCircleIntegration
            .redeemTokensWithPayload(redeemParameters)
            .then(async (tx) => {
              const receipt = await tx.wait();
              return receipt;
            });
        } catch (e: any) {
          expect(
            e.error.reason,
            "execution reverted: CIRCLE_INTEGRATION: failed to mint tokens"
          ).to.be.equal;
          failed = true;
        }

        // confirm that the call failed
        expect(failed).is.true;
      }
    });
  });
});
