import { ethers } from "ethers";
import { tryNativeToHexString } from "@certusone/wormhole-sdk";
import { sign } from "@noble/secp256k1";

const circleIntegrationModule =
  "0x000000000000000000000000000000436972636c65496e746567726174696f6e";
const GOVERNANCE_UPGRADE_ACTION = 3;
const governanceChainId = 1;
const governanceContract =
  "0x0000000000000000000000000000000000000000000000000000000000000004";

export interface Guardian {
  /**
   * Private key in hexadecimal string 0x encoded.
   */
  key: string;
  /**
   * Index of the public key in the current Guardian set.
   */
  index: number;
}

export interface GuardianSet {
  guardians: Guardian[];
  id: number;
}

export function doubleKeccak256(body: ethers.BytesLike) {
  return ethers.utils.keccak256(ethers.utils.keccak256(body));
}

export function createCircleIntegrationUpgradeVAA(
  chainId: number,
  newAddress: string,
  guardianSet: GuardianSet,
) {
  /*
      bytes32 module;
        uint8 action;
        uint16 chain;
        bytes32 newContract; //listed as address in the struct, but is actually bytes32 inside the VAA
      */

  const payload = ethers.utils.solidityPack(
    ["bytes32", "uint8", "uint16", "bytes32"],
    [
      circleIntegrationModule,
      GOVERNANCE_UPGRADE_ACTION,
      chainId,
      "0x" + tryNativeToHexString(newAddress, "ethereum"),
    ],
  );

  return encodeAndSignGovernancePayload(payload, guardianSet);
}

export function encodeAndSignGovernancePayload(
  payload: string,
  guardianSet: GuardianSet,
): string {
  const timestamp = Math.floor(Date.now() / 1000);
  const nonce = 1;
  const sequence = 1;
  const consistencyLevel = 1;
  const vaaVersion = 1;

  const encodedVAABody = ethers.utils.solidityPack(
    ["uint32", "uint32", "uint16", "bytes32", "uint64", "uint8", "bytes"],
    [
      timestamp,
      nonce,
      governanceChainId,
      governanceContract,
      sequence,
      consistencyLevel,
      payload,
    ],
  );

  const hash = doubleKeccak256(encodedVAABody).substring(2);

  const signatures = guardianSet.guardians
    .map(({ key, index }) => {
      const signature = sign(hash, key);
      if (signature.recovery === undefined)
        throw new Error(`Failed to sign message: missing recovery id`);

      // Remember that each signature is accompanied by the guardian index.
      const packSig = ethers.utils.solidityPack(
        ["uint8", "bytes32", "bytes32", "uint8"],
        [
          index,
          ethers.utils.hexZeroPad(ethers.utils.hexlify(signature.r), 32),
          ethers.utils.hexZeroPad(ethers.utils.hexlify(signature.s), 32),
          signature.recovery,
        ],
      );
      return packSig.substring(2);
    })
    .join("");

  const vm = [
    ethers.utils
      .solidityPack(
        ["uint8", "uint32", "uint8"],
        [
          vaaVersion,
          // guardianSetIndex
          guardianSet.id,
          // number of signers
          guardianSet.guardians.length,
        ],
      )
      .substring(2),
    signatures,
    encodedVAABody.substring(2),
  ].join("");

  return "0x" + vm;
}
