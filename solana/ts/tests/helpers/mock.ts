import { coalesceChainId, parseVaa, tryNativeToHexString } from "@certusone/wormhole-sdk";
import { MockEmitter, MockGuardians } from "@certusone/wormhole-sdk/lib/cjs/mock";
import { derivePostedVaaKey } from "@certusone/wormhole-sdk/lib/cjs/solana/wormhole";
import { Connection, Keypair, PublicKey } from "@solana/web3.js";
import { ethers } from "ethers";
import { Deposit } from "../../src";
import {
    ETHEREUM_WORMHOLE_CCTP_ADDRESS,
    GUARDIAN_KEY,
    WORMHOLE_CORE_BRIDGE_ADDRESS,
} from "./consts";
import { postVaa } from "./utils";

export type UpgradeContract = {
    targetChain: number;
    implementation: PublicKey;
};

export type RegisterEmitterAndDomain = {
    targetChain: number;
    foreignChain: number;
    foreignEmitter: Array<number>;
    cctpDomain: number;
};

export type WormholeCctpDecree = {
    upgradeContract?: UpgradeContract;
    registerEmitterAndDomain?: RegisterEmitterAndDomain;
};

export async function postGovVaa(
    connection: Connection,
    payer: Keypair,
    guardians: MockGuardians,
    sequence: bigint,
    decree: WormholeCctpDecree,
    options: {
        governanceEmitter?: MockEmitter;
        coreBridgeAddress?: PublicKey;
    } = {},
) {
    const { governanceEmitter: inputGovEmitter, coreBridgeAddress: inputCoreBridgeAddress } =
        options;
    const govEmitter =
        inputGovEmitter ??
        new MockEmitter(
            "0000000000000000000000000000000000000000000000000000000000000004",
            1,
            Number(sequence),
        );

    const payload = (() => {
        if (decree.registerEmitterAndDomain !== undefined) {
            const { targetChain, foreignChain, foreignEmitter, cctpDomain } =
                decree.registerEmitterAndDomain;

            const payload = Buffer.alloc(32 + 1 + 2 + 2 + 32 + 4);
            // Action.
            payload.writeUInt8(2, 32);
            // Data.
            payload.writeUInt16BE(targetChain, 33);
            payload.writeUInt16BE(foreignChain, 35);
            payload.set(foreignEmitter, 37);
            payload.writeUInt32BE(cctpDomain, 69);

            return payload;
        } else {
            const { targetChain, implementation } = decree.upgradeContract;

            const payload = Buffer.alloc(32 + 1 + 2 + 32);
            // Action.
            payload.writeUInt8(3, 32);
            // Data.
            payload.writeUInt16BE(targetChain, 33);
            payload.set(implementation.toBuffer(), 35);
            return payload;
        }
    })();

    const moduleName = "CircleIntegration";
    payload.set(Buffer.from(moduleName), 32 - moduleName.length);

    const published = govEmitter.publishMessage(
        0, // nonce,
        payload,
        0, // consistencyLevel
        12345678, // timestamp
    );
    const vaaBuf = guardians.addSignatures(published, [0]);

    await postVaa(connection, payer, vaaBuf, inputCoreBridgeAddress);

    return derivePostedVaaKey(
        inputCoreBridgeAddress ?? WORMHOLE_CORE_BRIDGE_ADDRESS,
        parseVaa(vaaBuf).hash,
    );
}

export async function postDepositVaa(
    connection: Connection,
    payer: Keypair,
    guardians: MockGuardians,
    sequence: bigint,
    deposit: Deposit,
    overrides: { ethEmitterAddress?: string } = {},
) {
    const { ethEmitterAddress: inputEthEmitterAddress } = overrides;

    const chainName = "ethereum";
    const foreignEmitter = new MockEmitter(
        tryNativeToHexString(inputEthEmitterAddress ?? ETHEREUM_WORMHOLE_CCTP_ADDRESS, chainName),
        coalesceChainId(chainName),
        Number(sequence),
    );

    const published = foreignEmitter.publishMessage(
        0, // nonce,
        deposit.encode(),
        0, // consistencyLevel
        12345678, // timestamp
    );
    const vaaBuf = guardians.addSignatures(published, [0]);

    await postVaa(connection, payer, vaaBuf);

    return derivePostedVaaKey(WORMHOLE_CORE_BRIDGE_ADDRESS, parseVaa(vaaBuf).hash);
}

export class CircleAttester {
    attester: ethers.utils.SigningKey;

    constructor() {
        this.attester = new ethers.utils.SigningKey("0x" + GUARDIAN_KEY);
    }

    createAttestation(message: Buffer | Uint8Array) {
        const signature = this.attester.signDigest(ethers.utils.keccak256(message));

        const attestation = Buffer.alloc(65);
        attestation.set(ethers.utils.arrayify(signature.r), 0);
        attestation.set(ethers.utils.arrayify(signature.s), 32);

        const recoveryId = signature.recoveryParam;
        attestation.writeUInt8(recoveryId < 27 ? recoveryId + 27 : recoveryId, 64);

        return attestation;
    }
}
