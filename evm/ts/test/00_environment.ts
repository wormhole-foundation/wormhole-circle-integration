import { expect } from "chai";
import { ethers } from "ethers";
import {
  CHAIN_ID_AVAX,
  CHAIN_ID_ETH,
  tryNativeToHexString,
} from "@certusone/wormhole-sdk";
import { IWormhole__factory } from "../src/ethers-contracts";
import {
  AVAX_FORK_CHAIN_ID,
  AVAX_LOCALHOST,
  AVAX_USDC_TOKEN_ADDRESS,
  AVAX_WORMHOLE_ADDRESS,
  ETH_FORK_CHAIN_ID,
  ETH_LOCALHOST,
  ETH_USDC_TOKEN_ADDRESS,
  ETH_WORMHOLE_ADDRESS,
  GUARDIAN_PRIVATE_KEY,
  WALLET_PRIVATE_KEY,
  WORMHOLE_GUARDIAN_SET_INDEX,
  WORMHOLE_MESSAGE_FEE,
} from "./helpers/consts";

describe("Environment Test", () => {
  describe("Global", () => {
    it("Environment Variables", () => {
      expect(WORMHOLE_MESSAGE_FEE).is.not.undefined;
      expect(WORMHOLE_GUARDIAN_SET_INDEX).is.not.undefined;
      expect(GUARDIAN_PRIVATE_KEY).is.not.undefined;
      expect(WALLET_PRIVATE_KEY).is.not.undefined;
    });
  });

  describe("Ethereum Goerli Testnet Fork", () => {
    describe("Environment", () => {
      it("Variables", () => {
        expect(ETH_LOCALHOST).is.not.undefined;
        expect(ETH_FORK_CHAIN_ID).is.not.undefined;
        expect(ETH_WORMHOLE_ADDRESS).is.not.undefined;
        expect(ETH_USDC_TOKEN_ADDRESS).is.not.undefined;
      });
    });

    describe("RPC", () => {
      const provider = new ethers.providers.StaticJsonRpcProvider(
        ETH_LOCALHOST
      );
      const wormhole = IWormhole__factory.connect(
        ETH_WORMHOLE_ADDRESS,
        provider
      );

      it("Chain ID", async () => {
        const network = await provider.getNetwork();
        expect(network.chainId).to.equal(ETH_FORK_CHAIN_ID);
      });

      it("Wormhole", async () => {
        const chainId = await wormhole.chainId();
        expect(chainId).to.equal(CHAIN_ID_ETH as number);

        const messageFee: ethers.BigNumber = await wormhole.messageFee();
        expect(messageFee.eq(WORMHOLE_MESSAGE_FEE)).to.be.true;

        // Override guardian set
        {
          // Check guardian set index
          const guardianSetIndex = await wormhole.getCurrentGuardianSetIndex();
          expect(guardianSetIndex).to.equal(WORMHOLE_GUARDIAN_SET_INDEX);

          // Override guardian set
          const abiCoder = ethers.utils.defaultAbiCoder;

          // Get slot for Guardian Set at the current index
          const guardianSetSlot = ethers.utils.keccak256(
            abiCoder.encode(["uint32", "uint256"], [guardianSetIndex, 2])
          );

          // Overwrite all but first guardian set to zero address. This isn't
          // necessary, but just in case we inadvertently access these slots
          // for any reason.
          const numGuardians = await provider
            .getStorageAt(wormhole.address, guardianSetSlot)
            .then((value) => ethers.BigNumber.from(value).toBigInt());
          for (let i = 1; i < numGuardians; ++i) {
            await provider.send("anvil_setStorageAt", [
              wormhole.address,
              abiCoder.encode(
                ["uint256"],
                [
                  ethers.BigNumber.from(
                    ethers.utils.keccak256(guardianSetSlot)
                  ).add(i),
                ]
              ),
              ethers.utils.hexZeroPad("0x0", 32),
            ]);
          }

          // Now overwrite the first guardian key with the devnet key specified
          // in the function argument.
          const devnetGuardian = new ethers.Wallet(GUARDIAN_PRIVATE_KEY)
            .address;
          await provider.send("anvil_setStorageAt", [
            wormhole.address,
            abiCoder.encode(
              ["uint256"],
              [
                ethers.BigNumber.from(
                  ethers.utils.keccak256(guardianSetSlot)
                ).add(
                  0 // just explicit w/ index 0
                ),
              ]
            ),
            ethers.utils.hexZeroPad(devnetGuardian, 32),
          ]);

          // Change the length to 1 guardian
          await provider.send("anvil_setStorageAt", [
            wormhole.address,
            guardianSetSlot,
            ethers.utils.hexZeroPad("0x1", 32),
          ]);

          // Confirm guardian set override
          const guardians = await wormhole
            .getGuardianSet(guardianSetIndex)
            .then(
              (guardianSet: any) => guardianSet[0] // first element is array of keys
            );
          expect(guardians.length).to.equal(1);
          expect(guardians[0]).to.equal(devnetGuardian);
        }
      });
    });

    describe("Wormhole SDK", () => {
      const provider = new ethers.providers.StaticJsonRpcProvider(
        ETH_LOCALHOST
      );

      it("tryNativeToHexString", async () => {
        const accounts = await provider.listAccounts();
        expect(tryNativeToHexString(accounts[0], "ethereum")).to.equal(
          "00000000000000000000000090f8bf6a479f320ead074411a4b0e7944ea8c9c1"
        );
      });
    });
  });

  describe("Avalanche Fuji Testnet Fork", () => {
    describe("Environment", () => {
      it("Variables", () => {
        expect(AVAX_LOCALHOST).is.not.undefined;
        expect(AVAX_FORK_CHAIN_ID).is.not.undefined;
        expect(AVAX_WORMHOLE_ADDRESS).is.not.undefined;
        expect(AVAX_USDC_TOKEN_ADDRESS).is.not.undefined;
      });
    });

    describe("RPC", () => {
      const provider = new ethers.providers.StaticJsonRpcProvider(
        AVAX_LOCALHOST
      );
      const wormhole = IWormhole__factory.connect(
        AVAX_WORMHOLE_ADDRESS,
        provider
      );

      it("Chain ID", async () => {
        const network = await provider.getNetwork();
        expect(network.chainId).to.equal(AVAX_FORK_CHAIN_ID);
      });

      it("Wormhole", async () => {
        const chainId = await wormhole.chainId();
        expect(chainId).to.equal(CHAIN_ID_AVAX as number);

        const messageFee: ethers.BigNumber = await wormhole.messageFee();
        expect(messageFee.eq(WORMHOLE_MESSAGE_FEE)).to.be.true;

        // Override guardian set
        {
          // Check guardian set index
          const guardianSetIndex = await wormhole.getCurrentGuardianSetIndex();
          expect(guardianSetIndex).to.equal(WORMHOLE_GUARDIAN_SET_INDEX);

          // Override guardian set
          const abiCoder = ethers.utils.defaultAbiCoder;

          // Get slot for Guardian Set at the current index
          const guardianSetSlot = ethers.utils.keccak256(
            abiCoder.encode(["uint32", "uint256"], [guardianSetIndex, 2])
          );

          // Overwrite all but first guardian set to zero address. This isn't
          // necessary, but just in case we inadvertently access these slots
          // for any reason.
          const numGuardians = await provider
            .getStorageAt(wormhole.address, guardianSetSlot)
            .then((value) => ethers.BigNumber.from(value).toBigInt());
          for (let i = 1; i < numGuardians; ++i) {
            await provider.send("anvil_setStorageAt", [
              wormhole.address,
              abiCoder.encode(
                ["uint256"],
                [
                  ethers.BigNumber.from(
                    ethers.utils.keccak256(guardianSetSlot)
                  ).add(i),
                ]
              ),
              ethers.utils.hexZeroPad("0x0", 32),
            ]);
          }

          // Now overwrite the first guardian key with the devnet key specified
          // in the function argument.
          const devnetGuardian = new ethers.Wallet(GUARDIAN_PRIVATE_KEY)
            .address;
          await provider.send("anvil_setStorageAt", [
            wormhole.address,
            abiCoder.encode(
              ["uint256"],
              [
                ethers.BigNumber.from(
                  ethers.utils.keccak256(guardianSetSlot)
                ).add(
                  0 // just explicit w/ index 0
                ),
              ]
            ),
            ethers.utils.hexZeroPad(devnetGuardian, 32),
          ]);

          // Change the length to 1 guardian
          await provider.send("anvil_setStorageAt", [
            wormhole.address,
            guardianSetSlot,
            ethers.utils.hexZeroPad("0x1", 32),
          ]);

          // Confirm guardian set override
          const guardians = await wormhole
            .getGuardianSet(guardianSetIndex)
            .then(
              (guardianSet: any) => guardianSet[0] // first element is array of keys
            );
          expect(guardians.length).to.equal(1);
          expect(guardians[0]).to.equal(devnetGuardian);
        }
      });
    });

    describe("Wormhole SDK", () => {
      const provider = new ethers.providers.StaticJsonRpcProvider(
        AVAX_LOCALHOST
      );

      it("tryNativeToHexString", async () => {
        const accounts = await provider.listAccounts();
        expect(tryNativeToHexString(accounts[0], "ethereum")).to.equal(
          "00000000000000000000000090f8bf6a479f320ead074411a4b0e7944ea8c9c1"
        );
      });
    });
  });
});
