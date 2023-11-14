import { postVaaSolana, solana as wormSolana } from "@certusone/wormhole-sdk";
import {
    AddressLookupTableAccount,
    ConfirmOptions,
    Connection,
    Keypair,
    PublicKey,
    Signer,
    SystemProgram,
    TransactionInstruction,
    TransactionMessage,
    VersionedTransaction,
} from "@solana/web3.js";
import { expect } from "chai";
import { execSync } from "child_process";
import { Err, Ok } from "ts-results";
import { WORMHOLE_CORE_BRIDGE_ADDRESS } from "./consts";

export function expectDeepEqual<T>(a: T, b: T) {
    expect(JSON.stringify(a)).to.equal(JSON.stringify(b));
}

async function confirmLatest(connection: Connection, signature: string) {
    return connection.getLatestBlockhash().then(({ blockhash, lastValidBlockHeight }) =>
        connection.confirmTransaction(
            {
                blockhash,
                lastValidBlockHeight,
                signature,
            },
            "confirmed",
        ),
    );
}

export async function expectIxOk(
    connection: Connection,
    instructions: TransactionInstruction[],
    signers: Signer[],
    options: {
        addressLookupTableAccounts?: AddressLookupTableAccount[];
        confirmOptions?: ConfirmOptions;
    } = {},
) {
    const { addressLookupTableAccounts, confirmOptions } = options;
    return debugSendAndConfirmTransaction(connection, instructions, signers, {
        addressLookupTableAccounts,
        logError: true,
        confirmOptions,
    }).then((result) => result.unwrap());
}

export async function expectIxErr(
    connection: Connection,
    instructions: TransactionInstruction[],
    signers: Signer[],
    expectedError: string,
    options: {
        addressLookupTableAccounts?: AddressLookupTableAccount[];
        confirmOptions?: ConfirmOptions;
    } = {},
) {
    const { addressLookupTableAccounts, confirmOptions } = options;
    const errorMsg = await debugSendAndConfirmTransaction(connection, instructions, signers, {
        addressLookupTableAccounts,
        logError: false,
        confirmOptions,
    }).then((result) => {
        if (result.err) {
            return result.toString();
        } else {
            throw new Error("Expected transaction to fail");
        }
    });
    try {
        expect(errorMsg).includes(expectedError);
    } catch (err) {
        console.log(errorMsg);
        throw err;
    }
}

export async function expectIxOkDetails(
    connection: Connection,
    ixs: TransactionInstruction[],
    signers: Signer[],
    options: {
        addressLookupTableAccounts?: AddressLookupTableAccount[];
        confirmOptions?: ConfirmOptions;
    } = {},
) {
    const txSig = await expectIxOk(connection, ixs, signers, options);
    await confirmLatest(connection, txSig);
    return connection.getTransaction(txSig, {
        commitment: "confirmed",
        maxSupportedTransactionVersion: 0,
    });
}

async function debugSendAndConfirmTransaction(
    connection: Connection,
    instructions: TransactionInstruction[],
    signers: Signer[],
    options: {
        addressLookupTableAccounts?: AddressLookupTableAccount[];
        logError?: boolean;
        confirmOptions?: ConfirmOptions;
    } = {},
) {
    const { logError, confirmOptions, addressLookupTableAccounts } = options;

    const latestBlockhash = await connection.getLatestBlockhash();

    const messageV0 = new TransactionMessage({
        payerKey: signers[0].publicKey,
        recentBlockhash: latestBlockhash.blockhash,
        instructions,
    }).compileToV0Message(addressLookupTableAccounts);

    const tx = new VersionedTransaction(messageV0);

    // sign your transaction with the required `Signers`
    tx.sign(signers);

    return connection
        .sendTransaction(tx, confirmOptions)
        .then(async (signature) => {
            await connection.confirmTransaction(
                {
                    signature,
                    ...latestBlockhash,
                },
                confirmOptions === undefined ? "confirmed" : confirmOptions.commitment,
            );
            return new Ok(signature);
        })
        .catch((err) => {
            if (logError) {
                console.log(err);
            }
            if (err.logs !== undefined) {
                const logs: string[] = err.logs;
                return new Err(logs.join("\n"));
            } else {
                return new Err(err.message);
            }
        });
}

export async function postVaa(
    connection: Connection,
    payer: Keypair,
    vaaBuf: Buffer,
    coreBridgeAddress?: PublicKey,
) {
    await postVaaSolana(
        connection,
        new wormSolana.NodeWallet(payer).signTransaction,
        coreBridgeAddress ?? WORMHOLE_CORE_BRIDGE_ADDRESS,
        payer.publicKey,
        vaaBuf,
    );
}

export async function loadProgramBpf(
    artifactPath: string,
    bufferAuthority: PublicKey,
): Promise<PublicKey> {
    // Write keypair to temporary file.
    const keypath = `${__dirname}/../keys/pFCBP4bhqdSsrWUVTgqhPsLrfEdChBK17vgFM7TxjxQ.json`;

    // Invoke BPF Loader Upgradeable `write-buffer` instruction.
    const buffer = (() => {
        const output = execSync(`solana -u l -k ${keypath} program write-buffer ${artifactPath}`);
        return new PublicKey(output.toString().match(/^.{8}([A-Za-z0-9]+)/)[1]);
    })();

    // Invoke BPF Loader Upgradeable `set-buffer-authority` instruction.
    execSync(
        `solana -k ${keypath} program set-buffer-authority ${buffer.toString()} --new-buffer-authority ${bufferAuthority.toString()} -u localhost`,
    );

    // Sometimes the validator fails to fetch a blockhash after this buffer gets loaded, so we wait
    // a bit to ensure that doesn't happen. Uncomment this in if this is an issue.
    //await new Promise((resolve) => setTimeout(resolve, 5000));

    // Return the pubkey for the buffer (our new program implementation).
    return buffer;
}
