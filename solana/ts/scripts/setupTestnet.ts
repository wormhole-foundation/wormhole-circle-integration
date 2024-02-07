import {
    ChainName,
    coalesceChainId,
    parseVaa,
    tryNativeToUint8Array,
} from "@certusone/wormhole-sdk";
import { MockEmitter, MockGuardians } from "@certusone/wormhole-sdk/lib/cjs/mock";
import { NodeWallet, postVaaSolana } from "@certusone/wormhole-sdk/lib/cjs/solana";
import { derivePostedVaaKey } from "@certusone/wormhole-sdk/lib/cjs/solana/wormhole";
import { Connection, Keypair, Transaction, sendAndConfirmTransaction } from "@solana/web3.js";
import "dotenv/config";
import { CircleIntegrationProgram } from "../src";

const PROGRAM_ID = "wcihrWf1s91vfukW7LW8ZvR1rzpeZ9BrtZ8oyPkWK5d";

// Here we go.
main();

// impl

async function main() {
    let govSequence = 6920n;

    const connection = new Connection("https://api.devnet.solana.com", "confirmed");
    const circleIntegration = new CircleIntegrationProgram(connection, PROGRAM_ID);

    if (process.env.SOLANA_PRIVATE_KEY === undefined) {
        throw new Error("SOLANA_PRIVATE_KEY is undefined");
    }
    const payer = Keypair.fromSecretKey(Buffer.from(process.env.SOLANA_PRIVATE_KEY, "hex"));

    // Set up CCTP Program.
    //await intialize(circleIntegration, payer);

    // Register emitter and domain.
    {
        const foreignChain = "sepolia";
        const foreignEmitter = "0x2703483B1a5a7c577e8680de9Df8Be03c6f30e3c";
        const cctpDomain = 0;

        await registerEmitterAndDomain(
            circleIntegration,
            payer,
            govSequence++,
            foreignChain,
            foreignEmitter,
            cctpDomain,
        );
    }
    {
        const foreignChain = "avalanche";
        const foreignEmitter = "0x58f4C17449c90665891C42E14D34aae7a26A472e";
        const cctpDomain = 1;

        await registerEmitterAndDomain(
            circleIntegration,
            payer,
            govSequence++,
            foreignChain,
            foreignEmitter,
            cctpDomain,
        );
    }
    {
        const foreignChain = "optimism_sepolia";
        const foreignEmitter = "0x2703483B1a5a7c577e8680de9Df8Be03c6f30e3c";
        const cctpDomain = 2;

        await registerEmitterAndDomain(
            circleIntegration,
            payer,
            govSequence++,
            foreignChain,
            foreignEmitter,
            cctpDomain,
        );
    }
    {
        const foreignChain = "arbitrum_sepolia";
        const foreignEmitter = "0x2703483B1a5a7c577e8680de9Df8Be03c6f30e3c";
        const cctpDomain = 3;

        await registerEmitterAndDomain(
            circleIntegration,
            payer,
            govSequence++,
            foreignChain,
            foreignEmitter,
            cctpDomain,
        );
    }
    {
        const foreignChain = "base_sepolia";
        const foreignEmitter = "0x2703483B1a5a7c577e8680de9Df8Be03c6f30e3c";
        const cctpDomain = 6;

        await registerEmitterAndDomain(
            circleIntegration,
            payer,
            govSequence++,
            foreignChain,
            foreignEmitter,
            cctpDomain,
        );
    }
    {
        const foreignChain = "polygon";
        const foreignEmitter = "0x2703483B1a5a7c577e8680de9Df8Be03c6f30e3c";
        const cctpDomain = 7;

        await registerEmitterAndDomain(
            circleIntegration,
            payer,
            govSequence++,
            foreignChain,
            foreignEmitter,
            cctpDomain,
        );
    }
}

async function intialize(circleIntegration: CircleIntegrationProgram, payer: Keypair) {
    console.log("custodian", circleIntegration.custodianAddress().toString());

    const ix = await circleIntegration.initializeIx(payer.publicKey);

    const connection = circleIntegration.program.provider.connection;
    const txSig = await sendAndConfirmTransaction(connection, new Transaction().add(ix), [payer]);
    console.log("intialize", txSig);
}

async function registerEmitterAndDomain(
    circleIntegration: CircleIntegrationProgram,
    payer: Keypair,
    govSequence: bigint,
    foreignChain: ChainName,
    foreignEmitter: string,
    cctpDomain: number,
) {
    const connection = circleIntegration.program.provider.connection;

    const registeredEmitter = circleIntegration.registeredEmitterAddress(
        coalesceChainId(foreignChain),
    );
    const emitterAddress = Array.from(tryNativeToUint8Array(foreignEmitter, foreignChain));

    const exists = await connection.getAccountInfo(registeredEmitter).then((acct) => acct != null);
    if (exists) {
        const registered = await circleIntegration.fetchRegisteredEmitter(registeredEmitter);
        if (Buffer.from(registered.address).equals(Buffer.from(emitterAddress))) {
            console.log("already registered", foreignChain, foreignEmitter, cctpDomain);
            return;
        }
    }

    const govEmitter = new MockEmitter(
        "0000000000000000000000000000000000000000000000000000000000000004",
        1,
        Number(govSequence),
    );

    const payload = Buffer.alloc(32 + 1 + 2 + 2 + 32 + 4);
    // Action.
    payload.writeUInt8(2, 32);
    // Data.
    payload.writeUInt16BE(1, 33); // targetChain
    payload.writeUInt16BE(coalesceChainId(foreignChain), 35);
    payload.set(tryNativeToUint8Array(foreignEmitter, foreignChain), 37);
    payload.writeUInt32BE(cctpDomain, 69);

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

    const ix = await circleIntegration.registerEmitterAndDomainIx({
        payer: payer.publicKey,
        vaa,
    });
    const txSig = await sendAndConfirmTransaction(connection, new Transaction().add(ix), [payer]);
    console.log(
        "register emitter and domain",
        txSig,
        "chain",
        foreignChain,
        "addr",
        foreignEmitter,
        "domain",
        cctpDomain,
    );
}
