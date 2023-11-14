import { parseVaa, tryNativeToUint8Array } from "@certusone/wormhole-sdk";
import { MockEmitter, MockGuardians } from "@certusone/wormhole-sdk/lib/cjs/mock";
import { NodeWallet, postVaaSolana } from "@certusone/wormhole-sdk/lib/cjs/solana";
import { derivePostedVaaKey } from "@certusone/wormhole-sdk/lib/cjs/solana/wormhole";
import { Connection, Keypair, Transaction, sendAndConfirmTransaction } from "@solana/web3.js";
import "dotenv/config";
import { CircleIntegrationProgram } from "../src";

const PROGRAM_ID = "wCCTPvsyeL9qYqbHTv3DUAyzEfYcyHoYw5c4mgcbBeW";

// Modify this to the new implementation address.
const NEW_IMPLEMENTATION = "HCUGGoihMthPN6d4VGpH8xUPYUofgTgqnpYtwyca7PEh";

// Here we go.
main();

// impl

async function main() {
    let govSequence = 6910n;

    const connection = new Connection("https://api.devnet.solana.com", "confirmed");
    const circleIntegration = new CircleIntegrationProgram(connection, PROGRAM_ID);

    if (process.env.SOLANA_PRIVATE_KEY === undefined) {
        throw new Error("SOLANA_PRIVATE_KEY is undefined");
    }
    const payer = Keypair.fromSecretKey(Buffer.from(process.env.SOLANA_PRIVATE_KEY, "hex"));

    await upgradeContract(circleIntegration, payer, govSequence);
}

async function upgradeContract(
    circleIntegration: CircleIntegrationProgram,
    payer: Keypair,
    govSequence: bigint,
) {
    const connection = circleIntegration.program.provider.connection;

    const govEmitter = new MockEmitter(
        "0000000000000000000000000000000000000000000000000000000000000004",
        1,
        Number(govSequence),
    );

    const payload = Buffer.alloc(32 + 1 + 2 + 32);
    // Action.
    payload.writeUInt8(3, 32);
    // Data.
    payload.writeUInt16BE(1, 33); // targetChain
    payload.set(tryNativeToUint8Array(NEW_IMPLEMENTATION, "solana"), 35);

    const moduleName = "CircleIntegration";
    payload.set(Buffer.from(moduleName), 32 - moduleName.length);

    const published = govEmitter.publishMessage(
        0, // nonce,
        payload,
        0, // consistencyLevel
        12345678, // timestamp
    );

    if (process.env.GUARDIAN_PRIVATE_KEY === undefined) {
        throw new Error("GUARDIAN_PRIVATE_KEY is undefined");
    }
    const guardians = new MockGuardians(0, [process.env.GUARDIAN_PRIVATE_KEY]);
    const vaaBuf = guardians.addSignatures(published, [0]);

    await postVaaSolana(
        connection,
        new NodeWallet(payer).signTransaction,
        circleIntegration.coreBridgeProgramId(),
        payer.publicKey,
        vaaBuf,
    );

    const vaa = derivePostedVaaKey(circleIntegration.coreBridgeProgramId(), parseVaa(vaaBuf).hash);

    const ix = await circleIntegration.upgradeContractIx({
        payer: payer.publicKey,
        vaa,
    });
    const txSig = await sendAndConfirmTransaction(connection, new Transaction().add(ix), [payer]);
    console.log("upgrade contract", txSig);
}
