import * as wormholeSdk from "@certusone/wormhole-sdk";
import { MockGuardians } from "@certusone/wormhole-sdk/lib/cjs/mock";
import { getPostedMessage } from "@certusone/wormhole-sdk/lib/cjs/solana/wormhole";
import * as anchor from "@coral-xyz/anchor";
import * as splToken from "@solana/spl-token";
import { expect } from "chai";
import {
    CctpTokenBurnMessage,
    CircleIntegrationProgram,
    Deposit,
    DepositHeader,
    VaaAccount,
} from "../src";
import {
    CircleAttester,
    ETHEREUM_USDC_ADDRESS,
    ETHEREUM_WORMHOLE_CCTP_ADDRESS,
    GUARDIAN_KEY,
    PAYER_PRIVATE_KEY,
    USDC_MINT_ADDRESS,
    expectIxErr,
    expectIxOk,
    expectIxOkDetails,
    postDepositVaa,
    postGovVaa,
} from "./helpers";

const guardians = new MockGuardians(0, [GUARDIAN_KEY]);

describe("Circle Integration -- Localnet", () => {
    const connection = new anchor.web3.Connection("http://localhost:8899", "processed");
    const payer = anchor.web3.Keypair.fromSecretKey(PAYER_PRIVATE_KEY);

    const circleIntegration = new CircleIntegrationProgram(
        connection,
        "Wormho1eCirc1e1ntegration111111111111111111",
    );

    let lookupTableAddress: anchor.web3.PublicKey;

    describe("Setup", () => {
        it("Invoke `initialize`", async () => {
            const ix = await circleIntegration.initializeIx(payer.publicKey);
            await expectIxOk(connection, [ix], [payer]);
        });

        after("Setup Lookup Table", async () => {
            // Create.
            const [createIx, lookupTable] = await connection.getSlot("finalized").then((slot) =>
                anchor.web3.AddressLookupTableProgram.createLookupTable({
                    authority: payer.publicKey,
                    payer: payer.publicKey,
                    recentSlot: slot,
                }),
            );
            await expectIxOk(connection, [createIx], [payer]);

            const usdcCommonAccounts = circleIntegration.commonAccounts(USDC_MINT_ADDRESS);

            // Extend.
            const extendIx = anchor.web3.AddressLookupTableProgram.extendLookupTable({
                payer: payer.publicKey,
                authority: payer.publicKey,
                lookupTable,
                addresses: Object.values(usdcCommonAccounts).filter((key) => key !== undefined),
            });

            await expectIxOk(connection, [extendIx], [payer], {
                confirmOptions: { commitment: "finalized" },
            });

            lookupTableAddress = lookupTable;
        });
    });

    describe("Register Emitter and Domain", () => {
        const localVariables = new Map<string, any>();

        it("Cannot Invoke `register_emitter_and_domain` with Invalid Target Chain", async () => {
            const vaa = await postGovVaa(connection, payer, guardians, 0n, {
                registerEmitterAndDomain: {
                    targetChain: 69,
                    foreignChain: 2,
                    foreignEmitter: Array.from(
                        Buffer.from(
                            "000000000000000000000000deadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
                            "hex",
                        ),
                    ),
                    cctpDomain: 0,
                },
            });

            const ix = await circleIntegration.registerEmitterAndDomainIx({
                payer: payer.publicKey,
                vaa,
            });

            await expectIxErr(connection, [ix], [payer], "Error Code: GovernanceForAnotherChain");
        });

        it("Cannot Invoke `register_emitter_and_domain` with Invalid Governance", async () => {
            const vaa = await postGovVaa(connection, payer, guardians, 0n, {
                upgradeContract: {
                    targetChain: 1,
                    implementation: anchor.web3.PublicKey.default,
                },
            });

            const ix = await circleIntegration.registerEmitterAndDomainIx({
                payer: payer.publicKey,
                vaa,
                remoteTokenMessenger: new anchor.web3.PublicKey(
                    "Hazwi3jFQtLKc2ughi7HFXPkpDeso7DQaMR9Ks4afh3j",
                ),
            });

            await expectIxErr(connection, [ix], [payer], "Error Code: InvalidGovernanceAction");
        });

        it("Cannot Invoke `register_emitter_and_domain` with Invalid CCTP Domain", async () => {
            const vaa = await postGovVaa(connection, payer, guardians, 0n, {
                registerEmitterAndDomain: {
                    targetChain: 1,
                    foreignChain: 2,
                    foreignEmitter: Array.from(
                        Buffer.from(
                            "000000000000000000000000deadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
                            "hex",
                        ),
                    ),
                    cctpDomain: 6,
                },
            });

            const ix = await circleIntegration.registerEmitterAndDomainIx({
                payer: payer.publicKey,
                vaa,
            });

            await expectIxErr(connection, [ix], [payer], "Error Code: InvalidCctpDomain");
        });

        it("Invoke `register_emitter_and_domain`", async () => {
            const foreignChain = 2;
            const foreignEmitter = Array.from(
                wormholeSdk.tryNativeToUint8Array(ETHEREUM_WORMHOLE_CCTP_ADDRESS, "ethereum"),
            );
            const cctpDomain = 0;

            const vaa = await postGovVaa(connection, payer, guardians, 0n, {
                registerEmitterAndDomain: {
                    targetChain: 1,
                    foreignChain,
                    foreignEmitter,
                    cctpDomain,
                },
            });

            const ix = await circleIntegration.registerEmitterAndDomainIx({
                payer: payer.publicKey,
                vaa,
            });

            const registeredEmitter = circleIntegration.registeredEmitterAddress(foreignChain);

            // Verify that account does not exist before invoking ix.
            {
                const acct = await connection.getAccountInfo(registeredEmitter);
                expect(acct).is.null;
            }

            await expectIxOk(connection, [ix], [payer]);

            // Now check account contents.
            const registeredEmitterData =
                await circleIntegration.fetchRegisteredEmitter(registeredEmitter);
            expect(registeredEmitterData).to.eql({
                bump: 255,
                cctpDomain,
                chain: foreignChain,
                address: foreignEmitter,
            });

            localVariables.set("vaa", vaa);
            localVariables.set("registeredEmitter", registeredEmitter);
        });

        it("Cannot Invoke `register_emitter_and_domain` with Same Governance Sequence", async () => {
            const vaa = localVariables.get("vaa") as anchor.web3.PublicKey;
            expect(localVariables.delete("vaa")).is.true;

            const registeredEmitter = localVariables.get(
                "registeredEmitter",
            ) as anchor.web3.PublicKey;
            expect(localVariables.delete("registeredEmitter")).is.true;

            const ix = await circleIntegration.registerEmitterAndDomainIx({
                payer: payer.publicKey,
                vaa,
            });

            // NOTE: This error actually triggers because a registered emitter is already present.
            // In case something changes with registration, we will keep this test around (it could
            // fail if registration changes in the future).
            await expectIxErr(
                connection,
                [ix],
                [payer],
                `Allocate: account Address { address: ${registeredEmitter.toString()}, base: None } already in use`,
            );
        });

        it("Cannot Invoke `register_emitter_and_domain` with Updated Emitter on Same Chain", async () => {
            const foreignChain = 2;

            const foreignEmitter = Array.from(
                Buffer.from(
                    "000000000000000000000000deadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
                    "hex",
                ),
            );
            const cctpDomain = 0;

            const vaa = await postGovVaa(connection, payer, guardians, 1n, {
                registerEmitterAndDomain: {
                    targetChain: 1,
                    foreignChain,
                    foreignEmitter,
                    cctpDomain,
                },
            });

            const ix = await circleIntegration.registerEmitterAndDomainIx({
                payer: payer.publicKey,
                vaa,
            });

            const registeredEmtiter = circleIntegration.registeredEmitterAddress(foreignChain);

            // Show that the foreign emitter about to be registered is not already written to the
            // account.
            {
                const currentForeignEmitter = await circleIntegration
                    .fetchRegisteredEmitter(registeredEmtiter)
                    .then((registered) => registered.address);
                expect(currentForeignEmitter).not.eql(foreignEmitter);
            }

            await expectIxErr(
                connection,
                [ix],
                [payer],
                `Allocate: account Address { address: ${registeredEmtiter.toString()}, base: None } already in use`,
            );
        });
    });

    describe("Outbound Transfers", () => {
        it("Cannot Invoke `transfer_tokens_with_payload` for Zero Amount", async () => {
            const payerToken = splToken.getAssociatedTokenAddressSync(
                USDC_MINT_ADDRESS,
                payer.publicKey,
            );

            const targetChain = 2;
            const mintRecipient = Array.from(Buffer.alloc(32, "deadbeef", "hex"));
            const wormholeMessageNonce = 420;
            const inputPayload = Buffer.from("All your base are belong to us.");

            const coreMessage = anchor.web3.Keypair.generate();
            const cctpMessage = anchor.web3.Keypair.generate();
            const ix = await circleIntegration.transferTokensWithPayloadIx(
                {
                    payer: payer.publicKey,
                    mint: USDC_MINT_ADDRESS,
                    burnSource: payerToken,
                    coreMessage: coreMessage.publicKey,
                    cctpMessage: cctpMessage.publicKey,
                },
                {
                    amount: 0n,
                    targetChain,
                    mintRecipient,
                    wormholeMessageNonce,
                    payload: inputPayload,
                },
            );

            const approveIx = splToken.createApproveInstruction(
                payerToken,
                circleIntegration.custodianAddress(),
                payer.publicKey,
                1,
            );

            const lookupTableAccount = await connection
                .getAddressLookupTable(lookupTableAddress)
                .then((resp) => resp.value);

            /// NOTE: This is a CCTP Token Messenger Minter program error.
            await expectIxErr(
                connection,
                [approveIx, ix],
                [payer, coreMessage, cctpMessage],
                "Error Code: InvalidAmount",
                {
                    addressLookupTableAccounts: [lookupTableAccount],
                },
            );
        });

        it("Cannot Invoke `transfer_tokens_with_payload` with Invalid Mint Recipient", async () => {
            const payerToken = splToken.getAssociatedTokenAddressSync(
                USDC_MINT_ADDRESS,
                payer.publicKey,
            );

            const amount = 69n;
            const targetChain = 2;
            const wormholeMessageNonce = 420;
            const inputPayload = Buffer.from("All your base are belong to us.");

            const coreMessage = anchor.web3.Keypair.generate();
            const cctpMessage = anchor.web3.Keypair.generate();
            const ix = await circleIntegration.transferTokensWithPayloadIx(
                {
                    payer: payer.publicKey,
                    mint: USDC_MINT_ADDRESS,
                    burnSource: payerToken,
                    coreMessage: coreMessage.publicKey,
                    cctpMessage: cctpMessage.publicKey,
                },
                {
                    amount,
                    targetChain,
                    mintRecipient: new Array(32),
                    wormholeMessageNonce,
                    payload: inputPayload,
                },
            );

            const approveIx = splToken.createApproveInstruction(
                payerToken,
                circleIntegration.custodianAddress(),
                payer.publicKey,
                amount,
            );

            const lookupTableAccount = await connection
                .getAddressLookupTable(lookupTableAddress)
                .then((resp) => resp.value);

            /// NOTE: This is a CCTP Token Messenger Minter program error.
            await expectIxErr(
                connection,
                [approveIx, ix],
                [payer, coreMessage, cctpMessage],
                "Error Code: InvalidMintRecipient",
                {
                    addressLookupTableAccounts: [lookupTableAccount],
                },
            );
        });

        it("Cannot Invoke `transfer_tokens_with_payload` if Custodian Not Delegated Authority", async () => {
            const payerToken = splToken.getAssociatedTokenAddressSync(
                USDC_MINT_ADDRESS,
                payer.publicKey,
            );

            const amount = 69n;
            const targetChain = 2;
            const mintRecipient = Array.from(Buffer.alloc(32, "deadbeef", "hex"));
            const wormholeMessageNonce = 420;
            const inputPayload = Buffer.from("All your base are belong to us.");

            const coreMessage = anchor.web3.Keypair.generate();
            const cctpMessage = anchor.web3.Keypair.generate();
            const ix = await circleIntegration.transferTokensWithPayloadIx(
                {
                    payer: payer.publicKey,
                    mint: USDC_MINT_ADDRESS,
                    burnSource: payerToken,
                    coreMessage: coreMessage.publicKey,
                    cctpMessage: cctpMessage.publicKey,
                },
                {
                    amount,
                    targetChain,
                    mintRecipient,
                    wormholeMessageNonce,
                    payload: inputPayload,
                },
            );

            const lookupTableAccount = await connection
                .getAddressLookupTable(lookupTableAddress)
                .then((resp) => resp.value);

            // NOTE: This is an SPL Token program error.
            await expectIxErr(
                connection,
                [ix],
                [payer, coreMessage, cctpMessage],
                "Error: owner does not match",
                {
                    addressLookupTableAccounts: [lookupTableAccount],
                },
            );
        });

        it("Invoke `transfer_tokens_with_payload`", async () => {
            const payerToken = splToken.getAssociatedTokenAddressSync(
                USDC_MINT_ADDRESS,
                payer.publicKey,
            );

            const amount = 69n;
            const targetChain = 2;
            const mintRecipient = Array.from(Buffer.alloc(32, "deadbeef", "hex"));
            const wormholeMessageNonce = 420;
            const inputPayload = Buffer.from("All your base are belong to us.");

            const coreMessage = anchor.web3.Keypair.generate();
            const cctpMessage = anchor.web3.Keypair.generate();
            const ix = await circleIntegration.transferTokensWithPayloadIx(
                {
                    payer: payer.publicKey,
                    mint: USDC_MINT_ADDRESS,
                    burnSource: payerToken,
                    coreMessage: coreMessage.publicKey,
                    cctpMessage: cctpMessage.publicKey,
                },
                {
                    amount,
                    targetChain,
                    mintRecipient,
                    wormholeMessageNonce,
                    payload: inputPayload,
                },
            );

            const approveIx = splToken.createApproveInstruction(
                payerToken,
                circleIntegration.custodianAddress(),
                payer.publicKey,
                amount,
            );

            const balanceBefore = await splToken
                .getAccount(connection, payerToken)
                .then((token) => token.amount);

            const lookupTableAccount = await connection
                .getAddressLookupTable(lookupTableAddress)
                .then((resp) => resp.value);
            const txReceipt = await expectIxOkDetails(
                connection,
                [approveIx, ix],
                [payer, coreMessage, cctpMessage],
                {
                    addressLookupTableAccounts: [lookupTableAccount],
                },
            );

            // Balance check.
            const balanceAfter = await splToken
                .getAccount(connection, payerToken)
                .then((token) => token.amount);
            expect(balanceAfter + amount).to.equal(balanceBefore);

            // Check messages.
            const posted = await getPostedMessage(connection, coreMessage.publicKey);
            const { deposit, payload } = Deposit.decode(posted.message.payload);
            expect(payload).to.eql(inputPayload);

            const { message: encodedCctpMessage } = await circleIntegration
                .messageTransmitterProgram()
                .fetchMessageSent(cctpMessage.publicKey);

            const burnMessage = CctpTokenBurnMessage.decode(encodedCctpMessage);
            expect(burnMessage.sender).to.eql(
                Array.from(circleIntegration.custodianAddress().toBuffer()),
            );
            expect(burnMessage.mintRecipient).to.eql(mintRecipient);

            const {
                cctp: {
                    sourceDomain: sourceCctpDomain,
                    destinationDomain: destinationCctpDomain,
                    nonce: cctpNonce,
                    targetCaller,
                },
            } = burnMessage;
            expect(deposit).to.eql({
                tokenAddress: Array.from(USDC_MINT_ADDRESS.toBuffer()),
                amount,
                sourceCctpDomain,
                destinationCctpDomain,
                cctpNonce,
                burnSource: Array.from(payerToken.toBuffer()),
                mintRecipient,
                payloadLen: inputPayload.length,
            } as DepositHeader);

            const foreignEmitter = await circleIntegration
                .fetchRegisteredEmitter(circleIntegration.registeredEmitterAddress(targetChain))
                .then((registered) => registered.address);
            expect(targetCaller).to.eql(foreignEmitter);
        });
    });

    describe("Inbound Transfers", () => {
        let testCctpNonce = 2n ** 64n - 1n;

        // Hack to prevent math overflow error when invoking Circle programs.
        testCctpNonce -= 2n * 6400n;

        let wormholeSequence = 0n;

        const localVariables = new Map<string, any>();

        it("Cannot Invoke `redeem_transfer_with_payload` with Invalid VAA Account (Not Owned by Core Bridge)", async () => {
            const mintRecipientAuthority = anchor.web3.Keypair.generate();
            const mintRecipient = await splToken.createAccount(
                connection,
                payer,
                USDC_MINT_ADDRESS,
                mintRecipientAuthority.publicKey,
            );

            const encodedMintRecipient = Array.from(mintRecipient.toBuffer());
            const sourceCctpDomain = 0;
            const cctpNonce = testCctpNonce++;
            const amount = 69n;

            // Concoct a Circle message.
            const burnSource = Array.from(Buffer.alloc(32, "beefdead", "hex"));
            const { burnMessage, destinationCctpDomain, encodedCctpMessage, cctpAttestation } =
                await craftCctpTokenBurnMessage(
                    circleIntegration,
                    sourceCctpDomain,
                    cctpNonce,
                    encodedMintRecipient,
                    amount,
                    burnSource,
                );

            const payload = Buffer.from("Somebody set up us the bomb.");
            const deposit = new Deposit(
                {
                    tokenAddress: burnMessage.burnTokenAddress,
                    amount,
                    sourceCctpDomain,
                    destinationCctpDomain,
                    cctpNonce,
                    burnSource,
                    mintRecipient: encodedMintRecipient,
                    payloadLen: payload.length,
                },
                payload,
            );

            const vaa = await postDepositVaa(
                connection,
                payer,
                guardians,
                wormholeSequence++,
                deposit,
            );

            const computeIx = anchor.web3.ComputeBudgetProgram.setComputeUnitLimit({
                units: 300_000,
            });
            const ix = await circleIntegration.redeemTokensWithPayloadIx(
                {
                    payer: payer.publicKey,
                    vaa,
                },
                { encodedCctpMessage, cctpAttestation },
            );

            // Replace VAA account with something else not owned by the Wormhole Core Bridge.
            ix.keys[ix.keys.findIndex((meta) => meta.pubkey.equals(vaa))].pubkey =
                anchor.web3.SYSVAR_CLOCK_PUBKEY;

            const lookupTableAccount = await connection
                .getAddressLookupTable(lookupTableAddress)
                .then((resp) => resp.value);
            await expectIxErr(
                connection,
                [computeIx, ix],
                [payer, mintRecipientAuthority],
                "Error Code: ConstraintOwner",
                {
                    addressLookupTableAccounts: [lookupTableAccount],
                },
            );
        });

        it("Cannot Invoke `redeem_transfer_with_payload` with Unknown Emitter", async () => {
            const mintRecipientAuthority = anchor.web3.Keypair.generate();
            const mintRecipient = await splToken.createAccount(
                connection,
                payer,
                USDC_MINT_ADDRESS,
                mintRecipientAuthority.publicKey,
            );

            const encodedMintRecipient = Array.from(mintRecipient.toBuffer());
            const sourceCctpDomain = 0;
            const cctpNonce = testCctpNonce++;
            const amount = 69n;

            // Concoct a Circle message.
            const burnSource = Array.from(Buffer.alloc(32, "beefdead", "hex"));
            const { destinationCctpDomain, burnMessage, encodedCctpMessage, cctpAttestation } =
                await craftCctpTokenBurnMessage(
                    circleIntegration,
                    sourceCctpDomain,
                    cctpNonce,
                    encodedMintRecipient,
                    amount,
                    burnSource,
                );

            const payload = Buffer.from("Somebody set up us the bomb.");
            const deposit = new Deposit(
                {
                    tokenAddress: burnMessage.burnTokenAddress,
                    amount,
                    sourceCctpDomain,
                    destinationCctpDomain,
                    cctpNonce,
                    burnSource,
                    mintRecipient: encodedMintRecipient,
                    payloadLen: payload.length,
                },
                payload,
            );

            const vaa = await postDepositVaa(
                connection,
                payer,
                guardians,
                wormholeSequence++,
                deposit,
                {
                    ethEmitterAddress: "0xfbadc0defbadc0defbadc0defbadc0defbadc0de",
                },
            );

            const computeIx = anchor.web3.ComputeBudgetProgram.setComputeUnitLimit({
                units: 300_000,
            });
            const ix = await circleIntegration.redeemTokensWithPayloadIx(
                {
                    payer: payer.publicKey,
                    vaa,
                },
                { encodedCctpMessage, cctpAttestation },
            );

            const lookupTableAccount = await connection
                .getAddressLookupTable(lookupTableAddress)
                .then((resp) => resp.value);
            await expectIxErr(
                connection,
                [computeIx, ix],
                [payer, mintRecipientAuthority],
                "UnknownEmitter",
                {
                    addressLookupTableAccounts: [lookupTableAccount],
                },
            );
        });

        it.skip("Cannot Invoke `redeem_transfer_with_payload` with Invalid Message", async () => {
            // TODO
        });

        it("Cannot Invoke `redeem_transfer_with_payload` with Invalid Mint Recipient", async () => {
            const mintRecipientAuthority = anchor.web3.Keypair.generate();
            const mintRecipient = await splToken.createAccount(
                connection,
                payer,
                USDC_MINT_ADDRESS,
                mintRecipientAuthority.publicKey,
            );

            const encodedMintRecipient = Array.from(mintRecipient.toBuffer());
            const sourceCctpDomain = 0;
            const cctpNonce = testCctpNonce++;
            const amount = 69n;

            // Concoct a Circle message.
            const burnSource = Array.from(Buffer.alloc(32, "beefdead", "hex"));
            const { destinationCctpDomain, burnMessage, encodedCctpMessage, cctpAttestation } =
                await craftCctpTokenBurnMessage(
                    circleIntegration,
                    sourceCctpDomain,
                    cctpNonce,
                    encodedMintRecipient,
                    amount,
                    burnSource,
                );

            const payload = Buffer.from("Somebody set up us the bomb.");
            const deposit = new Deposit(
                {
                    tokenAddress: burnMessage.burnTokenAddress,
                    amount,
                    sourceCctpDomain,
                    destinationCctpDomain,
                    cctpNonce,
                    burnSource,
                    mintRecipient: new Array(32),
                    payloadLen: payload.length,
                },
                payload,
            );

            const vaa = await postDepositVaa(
                connection,
                payer,
                guardians,
                wormholeSequence++,
                deposit,
            );

            const computeIx = anchor.web3.ComputeBudgetProgram.setComputeUnitLimit({
                units: 300_000,
            });
            const ix = await circleIntegration.redeemTokensWithPayloadIx(
                {
                    payer: payer.publicKey,
                    vaa,
                },
                { encodedCctpMessage, cctpAttestation },
            );

            const lookupTableAccount = await connection
                .getAddressLookupTable(lookupTableAddress)
                .then((resp) => resp.value);
            await expectIxErr(
                connection,
                [computeIx, ix],
                [payer, mintRecipientAuthority],
                "Error Code: InvalidMintRecipient",
                {
                    addressLookupTableAccounts: [lookupTableAccount],
                },
            );
        });

        it("Cannot Invoke `redeem_transfer_with_payload` with Mint Recipient Authority not Token Owner", async () => {
            const mintRecipientAuthority = anchor.web3.Keypair.generate();
            const mintRecipient = await splToken.createAccount(
                connection,
                payer,
                USDC_MINT_ADDRESS,
                mintRecipientAuthority.publicKey,
            );

            const someoneElse = anchor.web3.Keypair.generate();

            const encodedMintRecipient = Array.from(mintRecipient.toBuffer());
            const sourceCctpDomain = 0;
            const cctpNonce = testCctpNonce++;
            const amount = 69n;

            // Concoct a Circle message.
            const burnSource = Array.from(Buffer.alloc(32, "beefdead", "hex"));
            const { destinationCctpDomain, burnMessage, encodedCctpMessage, cctpAttestation } =
                await craftCctpTokenBurnMessage(
                    circleIntegration,
                    sourceCctpDomain,
                    cctpNonce,
                    encodedMintRecipient,
                    amount,
                    burnSource,
                );

            const payload = Buffer.from("Somebody set up us the bomb.");
            const deposit = new Deposit(
                {
                    tokenAddress: burnMessage.burnTokenAddress,
                    amount,
                    sourceCctpDomain,
                    destinationCctpDomain,
                    cctpNonce,
                    burnSource,
                    mintRecipient: encodedMintRecipient,
                    payloadLen: payload.length,
                },
                payload,
            );

            const vaa = await postDepositVaa(
                connection,
                payer,
                guardians,
                wormholeSequence++,
                deposit,
            );

            const computeIx = anchor.web3.ComputeBudgetProgram.setComputeUnitLimit({
                units: 300_000,
            });
            const ix = await circleIntegration.redeemTokensWithPayloadIx(
                {
                    payer: payer.publicKey,
                    vaa,
                    mintRecipientAuthority: someoneElse.publicKey,
                },
                { encodedCctpMessage, cctpAttestation },
            );

            const lookupTableAccount = await connection
                .getAddressLookupTable(lookupTableAddress)
                .then((resp) => resp.value);
            await expectIxErr(
                connection,
                [computeIx, ix],
                [payer, someoneElse],
                "Error Code: ConstraintTokenOwner",
                {
                    addressLookupTableAccounts: [lookupTableAccount],
                },
            );
        });

        it("Cannot Invoke `redeem_transfer_with_payload` with Source CCTP Domain Mismatch", async () => {
            const mintRecipientAuthority = anchor.web3.Keypair.generate();
            const mintRecipient = await splToken.createAccount(
                connection,
                payer,
                USDC_MINT_ADDRESS,
                mintRecipientAuthority.publicKey,
            );

            const encodedMintRecipient = Array.from(mintRecipient.toBuffer());
            const sourceCctpDomain = 0;
            const cctpNonce = testCctpNonce++;
            const amount = 69n;

            // Concoct a Circle message.
            const burnSource = Array.from(Buffer.alloc(32, "beefdead", "hex"));
            const { destinationCctpDomain, burnMessage, encodedCctpMessage, cctpAttestation } =
                await craftCctpTokenBurnMessage(
                    circleIntegration,
                    sourceCctpDomain,
                    cctpNonce,
                    encodedMintRecipient,
                    amount,
                    burnSource,
                );

            const payload = Buffer.from("Somebody set up us the bomb.");
            const deposit = new Deposit(
                {
                    tokenAddress: burnMessage.burnTokenAddress,
                    amount,
                    sourceCctpDomain: sourceCctpDomain + 1,
                    destinationCctpDomain,
                    cctpNonce,
                    burnSource,
                    mintRecipient: encodedMintRecipient,
                    payloadLen: payload.length,
                },
                payload,
            );

            const vaa = await postDepositVaa(
                connection,
                payer,
                guardians,
                wormholeSequence++,
                deposit,
            );

            const computeIx = anchor.web3.ComputeBudgetProgram.setComputeUnitLimit({
                units: 300_000,
            });
            const ix = await circleIntegration.redeemTokensWithPayloadIx(
                {
                    payer: payer.publicKey,
                    vaa,
                },
                { encodedCctpMessage, cctpAttestation },
            );

            const lookupTableAccount = await connection
                .getAddressLookupTable(lookupTableAddress)
                .then((resp) => resp.value);
            await expectIxErr(
                connection,
                [computeIx, ix],
                [payer, mintRecipientAuthority],
                "Error Code: SourceCctpDomainMismatch",
                {
                    addressLookupTableAccounts: [lookupTableAccount],
                },
            );
        });

        it("Cannot Invoke `redeem_transfer_with_payload` with Destination CCTP Domain Mismatch", async () => {
            const mintRecipientAuthority = anchor.web3.Keypair.generate();
            const mintRecipient = await splToken.createAccount(
                connection,
                payer,
                USDC_MINT_ADDRESS,
                mintRecipientAuthority.publicKey,
            );

            const encodedMintRecipient = Array.from(mintRecipient.toBuffer());
            const sourceCctpDomain = 0;
            const cctpNonce = testCctpNonce++;
            const amount = 69n;

            // Concoct a Circle message.
            const burnSource = Array.from(Buffer.alloc(32, "beefdead", "hex"));
            const { destinationCctpDomain, burnMessage, encodedCctpMessage, cctpAttestation } =
                await craftCctpTokenBurnMessage(
                    circleIntegration,
                    sourceCctpDomain,
                    cctpNonce,
                    encodedMintRecipient,
                    amount,
                    burnSource,
                );

            const payload = Buffer.from("Somebody set up us the bomb.");
            const deposit = new Deposit(
                {
                    tokenAddress: burnMessage.burnTokenAddress,
                    amount,
                    sourceCctpDomain,
                    destinationCctpDomain: destinationCctpDomain + 1,
                    cctpNonce,
                    burnSource,
                    mintRecipient: encodedMintRecipient,
                    payloadLen: payload.length,
                },
                payload,
            );

            const vaa = await postDepositVaa(
                connection,
                payer,
                guardians,
                wormholeSequence++,
                deposit,
            );

            const computeIx = anchor.web3.ComputeBudgetProgram.setComputeUnitLimit({
                units: 300_000,
            });
            const ix = await circleIntegration.redeemTokensWithPayloadIx(
                {
                    payer: payer.publicKey,
                    vaa,
                },
                { encodedCctpMessage, cctpAttestation },
            );

            const lookupTableAccount = await connection
                .getAddressLookupTable(lookupTableAddress)
                .then((resp) => resp.value);
            await expectIxErr(
                connection,
                [computeIx, ix],
                [payer, mintRecipientAuthority],
                "Error Code: DestinationCctpDomainMismatch",
                {
                    addressLookupTableAccounts: [lookupTableAccount],
                },
            );
        });

        it("Cannot Invoke `redeem_transfer_with_payload` with CCTP Nonce Mismatch", async () => {
            const mintRecipientAuthority = anchor.web3.Keypair.generate();
            const mintRecipient = await splToken.createAccount(
                connection,
                payer,
                USDC_MINT_ADDRESS,
                mintRecipientAuthority.publicKey,
            );

            const encodedMintRecipient = Array.from(mintRecipient.toBuffer());
            const sourceCctpDomain = 0;
            const cctpNonce = testCctpNonce++;
            const amount = 69n;

            // Concoct a Circle message.
            const burnSource = Array.from(Buffer.alloc(32, "beefdead", "hex"));
            const { destinationCctpDomain, burnMessage, encodedCctpMessage, cctpAttestation } =
                await craftCctpTokenBurnMessage(
                    circleIntegration,
                    sourceCctpDomain,
                    cctpNonce,
                    encodedMintRecipient,
                    amount,
                    burnSource,
                );

            const payload = Buffer.from("Somebody set up us the bomb.");
            const deposit = new Deposit(
                {
                    tokenAddress: burnMessage.burnTokenAddress,
                    amount,
                    sourceCctpDomain,
                    destinationCctpDomain,
                    cctpNonce: cctpNonce - 1n,
                    burnSource,
                    mintRecipient: encodedMintRecipient,
                    payloadLen: payload.length,
                },
                payload,
            );

            const vaa = await postDepositVaa(
                connection,
                payer,
                guardians,
                wormholeSequence++,
                deposit,
            );

            const computeIx = anchor.web3.ComputeBudgetProgram.setComputeUnitLimit({
                units: 300_000,
            });
            const ix = await circleIntegration.redeemTokensWithPayloadIx(
                {
                    payer: payer.publicKey,
                    vaa,
                },
                { encodedCctpMessage, cctpAttestation },
            );

            const lookupTableAccount = await connection
                .getAddressLookupTable(lookupTableAddress)
                .then((resp) => resp.value);
            await expectIxErr(
                connection,
                [computeIx, ix],
                [payer, mintRecipientAuthority],
                "Error Code: CctpNonceMismatch",
                {
                    addressLookupTableAccounts: [lookupTableAccount],
                },
            );
        });

        it("Invoke `redeem_transfer_with_payload`", async () => {
            const mintRecipientAuthority = anchor.web3.Keypair.generate();
            const mintRecipient = await splToken.createAccount(
                connection,
                payer,
                USDC_MINT_ADDRESS,
                mintRecipientAuthority.publicKey,
            );

            const encodedMintRecipient = Array.from(mintRecipient.toBuffer());
            const sourceCctpDomain = 0;
            const cctpNonce = testCctpNonce++;
            const amount = 69n;

            // Concoct a Circle message.
            const burnSource = Array.from(Buffer.alloc(32, "beefdead", "hex"));
            const { destinationCctpDomain, burnMessage, encodedCctpMessage, cctpAttestation } =
                await craftCctpTokenBurnMessage(
                    circleIntegration,
                    sourceCctpDomain,
                    cctpNonce,
                    encodedMintRecipient,
                    amount,
                    burnSource,
                );

            const payload = Buffer.from("Somebody set up us the bomb.");
            const deposit = new Deposit(
                {
                    tokenAddress: burnMessage.burnTokenAddress,
                    amount,
                    sourceCctpDomain,
                    destinationCctpDomain,
                    cctpNonce,
                    burnSource,
                    mintRecipient: encodedMintRecipient,
                    payloadLen: payload.length,
                },
                payload,
            );

            const vaa = await postDepositVaa(
                connection,
                payer,
                guardians,
                wormholeSequence++,
                deposit,
            );

            const computeIx = anchor.web3.ComputeBudgetProgram.setComputeUnitLimit({
                units: 300_000,
            });
            const ix = await circleIntegration.redeemTokensWithPayloadIx(
                {
                    payer: payer.publicKey,
                    vaa,
                },
                { encodedCctpMessage, cctpAttestation },
            );

            const balanceBefore = await splToken
                .getAccount(connection, mintRecipient)
                .then((token) => token.amount);

            const lookupTableAccount = await connection
                .getAddressLookupTable(lookupTableAddress)
                .then((resp) => resp.value);
            await expectIxOk(connection, [computeIx, ix], [payer, mintRecipientAuthority], {
                addressLookupTableAccounts: [lookupTableAccount],
            });

            // Balance check.
            const balanceAfter = await splToken
                .getAccount(connection, mintRecipient)
                .then((token) => token.amount);
            expect(balanceBefore + amount).to.equal(balanceAfter);

            localVariables.set("encodedCctpMessage", encodedCctpMessage);
            localVariables.set("cctpAttestation", cctpAttestation);
            localVariables.set("vaa", vaa);
            localVariables.set("mintRecipientAuthority", mintRecipientAuthority);
        });

        it("Cannot Invoke `redeem_tokens_with` with Same Messages", async () => {
            const encodedCctpMessage = localVariables.get("encodedCctpMessage") as Buffer;
            expect(localVariables.delete("encodedCctpMessage")).is.true;

            const cctpAttestation = localVariables.get("cctpAttestation") as Buffer;
            expect(localVariables.delete("cctpAttestation")).is.true;

            const vaa = localVariables.get("vaa") as anchor.web3.PublicKey;
            expect(localVariables.delete("vaa")).is.true;

            const mintRecipientAuthority = localVariables.get(
                "mintRecipientAuthority",
            ) as anchor.web3.Keypair;
            expect(localVariables.delete("mintRecipientAuthority")).is.true;

            const ix = await circleIntegration.redeemTokensWithPayloadIx(
                {
                    payer: payer.publicKey,
                    vaa,
                },
                { encodedCctpMessage, cctpAttestation },
            );

            const vaaHash = await VaaAccount.fetch(connection, vaa).then((vaa) => vaa.digest());
            const consumedVaa = circleIntegration.consumedVaaAddress(vaaHash);

            const lookupTableAccount = await connection
                .getAddressLookupTable(lookupTableAddress)
                .then((resp) => resp.value);
            await expectIxErr(
                connection,
                [ix],
                [payer, mintRecipientAuthority],
                `Allocate: account Address { address: ${consumedVaa.toString()}, base: None } already in use`,
                {
                    addressLookupTableAccounts: [lookupTableAccount],
                },
            );
        });
    });
});

async function craftCctpTokenBurnMessage(
    circleIntegration: CircleIntegrationProgram,
    sourceCctpDomain: number,
    cctpNonce: bigint,
    encodedMintRecipient: number[],
    amount: bigint,
    burnSource: number[],
    overrides: { destinationCctpDomain?: number } = {},
) {
    const { destinationCctpDomain: inputDestinationCctpDomain } = overrides;

    const messageTransmitterProgram = circleIntegration.messageTransmitterProgram();
    const { version, localDomain } = await messageTransmitterProgram.fetchMessageTransmitterConfig(
        messageTransmitterProgram.messageTransmitterConfigAddress(),
    );
    const destinationCctpDomain = inputDestinationCctpDomain ?? localDomain;

    const tokenMessengerMinterProgram = circleIntegration.tokenMessengerMinterProgram();
    const sourceTokenMessenger = await tokenMessengerMinterProgram
        .fetchRemoteTokenMessenger(
            tokenMessengerMinterProgram.remoteTokenMessengerAddress(sourceCctpDomain),
        )
        .then((remote) => remote.tokenMessenger);

    const burnMessage = new CctpTokenBurnMessage(
        {
            version,
            sourceDomain: sourceCctpDomain,
            destinationDomain: destinationCctpDomain,
            nonce: cctpNonce,
            sender: sourceTokenMessenger,
            recipient: Array.from(tokenMessengerMinterProgram.ID.toBuffer()), // targetTokenMessenger
            targetCaller: Array.from(circleIntegration.custodianAddress().toBuffer()), // targetCaller
        },
        0,
        Array.from(wormholeSdk.tryNativeToUint8Array(ETHEREUM_USDC_ADDRESS, "ethereum")), // sourceTokenAddress
        encodedMintRecipient,
        amount,
        burnSource,
    );

    const encodedCctpMessage = burnMessage.encode();
    const cctpAttestation = new CircleAttester().createAttestation(encodedCctpMessage);

    return {
        destinationCctpDomain,
        burnMessage,
        encodedCctpMessage,
        cctpAttestation,
    };
}
