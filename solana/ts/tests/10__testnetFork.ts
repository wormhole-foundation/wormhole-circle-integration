import { MockEmitter, MockGuardians } from "@certusone/wormhole-sdk/lib/cjs/mock";
import { Connection, Keypair, PublicKey, TransactionInstruction } from "@solana/web3.js";
import { expect } from "chai";
import { BPF_LOADER_UPGRADEABLE_ID, CircleIntegrationProgram } from "../src";
import {
    GUARDIAN_KEY,
    PAYER_PRIVATE_KEY,
    expectIxErr,
    expectIxOk,
    loadProgramBpf,
    postGovVaa,
} from "./helpers";

const WORMHOLE_CORE_BRIDGE_ADDRESS = new PublicKey("3u8hJUVTA4jH1wYAyUur7FFZVQ8H635K3tSHHF4ssjQ5");
const ARTIFACTS_PATH = `${__dirname}/artifacts/testnet_wormhole_circle_integration_solana.so`;

const guardians = new MockGuardians(0, [GUARDIAN_KEY]);

describe("Circle Integration -- Testnet Fork", () => {
    const connection = new Connection("http://localhost:8899", "processed");
    const payer = Keypair.fromSecretKey(PAYER_PRIVATE_KEY);

    const circleIntegration = new CircleIntegrationProgram(
        connection,
        "wcihrWf1s91vfukW7LW8ZvR1rzpeZ9BrtZ8oyPkWK5d",
    );

    describe("Upgrade Contract", () => {
        const localVariables = new Map<string, any>();

        it("Deploy Implementation", async () => {
            const implementation = await loadProgramBpf(
                ARTIFACTS_PATH,
                circleIntegration.upgradeAuthorityAddress(),
            );

            localVariables.set("implementation", implementation);
        });

        it("Invoke `upgrade_contract` on Forked Circle Integration", async () => {
            const implementation = localVariables.get("implementation") as PublicKey;
            expect(localVariables.delete("implementation")).is.true;

            const vaa = await postGovVaa(
                connection,
                payer,
                guardians,
                0n,
                {
                    upgradeContract: {
                        targetChain: 1,
                        implementation,
                    },
                },
                {
                    coreBridgeAddress: WORMHOLE_CORE_BRIDGE_ADDRESS,
                },
            );

            const ix = await circleIntegration.upgradeContractIx({
                payer: payer.publicKey,
                vaa,
            });

            await expectIxOk(connection, [ix], [payer]);
        });

        it("Deploy Same Implementation and Invoke `upgrade_contract` with Another VAA", async () => {
            const implementation = await loadProgramBpf(
                ARTIFACTS_PATH,
                circleIntegration.upgradeAuthorityAddress(),
            );

            const vaa = await postGovVaa(
                connection,
                payer,
                guardians,
                1n,
                {
                    upgradeContract: {
                        targetChain: 1,
                        implementation,
                    },
                },
                {
                    coreBridgeAddress: WORMHOLE_CORE_BRIDGE_ADDRESS,
                },
            );

            const ix = await circleIntegration.upgradeContractIx({
                payer: payer.publicKey,
                vaa,
            });

            await expectIxOk(connection, [ix], [payer]);

            // Save for later.
            localVariables.set("vaa", vaa);
        });

        it("Cannot Invoke `upgrade_contract` with Same VAA", async () => {
            const vaa = localVariables.get("vaa") as PublicKey;
            expect(localVariables.delete("vaa")).is.true;

            const ix = await circleIntegration.upgradeContractIx({
                payer: payer.publicKey,
                vaa,
            });

            // NOTE: The claim account created in the upgrade contract instruction doesn't trigger
            // the protection for a replay attack. The account data in the program data does. But
            // we will keep this test here just in case something changes in the future.
            await expectIxErr(connection, [ix], [payer], "invalid account data for instruction");
        });

        it("Cannot Invoke `upgrade_contract` with Implementation Mismatch", async () => {
            const implementation = await loadProgramBpf(
                ARTIFACTS_PATH,
                circleIntegration.upgradeAuthorityAddress(),
            );
            const anotherImplementation = await loadProgramBpf(
                ARTIFACTS_PATH,
                circleIntegration.upgradeAuthorityAddress(),
            );

            const vaa = await postGovVaa(
                connection,
                payer,
                guardians,
                0n,
                {
                    upgradeContract: {
                        targetChain: 1,
                        implementation: anotherImplementation,
                    },
                },
                {
                    coreBridgeAddress: WORMHOLE_CORE_BRIDGE_ADDRESS,
                },
            );

            // Create the upgrade instruction, but pass a different implementation.
            const ix = await circleIntegration.upgradeContractIx({
                payer: payer.publicKey,
                vaa,
                buffer: implementation,
            });

            await expectIxErr(connection, [ix], [payer], "Error Code: ImplementationMismatch");
        });

        it("Cannot Invoke `upgrade_contract` with Invalid Governance Emitter", async () => {
            const implementation = await loadProgramBpf(
                ARTIFACTS_PATH,
                circleIntegration.upgradeAuthorityAddress(),
            );

            // Create a bad governance emitter by using an invalid address.
            const invalidEmitter = new MockEmitter(
                circleIntegration.ID.toBuffer().toString("hex"),
                1,
                12121212,
            );

            const vaa = await postGovVaa(
                connection,
                payer,
                guardians,
                2n,
                {
                    upgradeContract: {
                        targetChain: 1,
                        implementation,
                    },
                },
                {
                    coreBridgeAddress: WORMHOLE_CORE_BRIDGE_ADDRESS,
                    governanceEmitter: invalidEmitter,
                },
            );

            // Create the upgrade instruction, but pass a different implementation.
            const ix = await circleIntegration.upgradeContractIx({
                payer: payer.publicKey,
                vaa,
                buffer: implementation,
            });

            await expectIxErr(connection, [ix], [payer], "Error Code: InvalidGovernanceEmitter");
        });

        it("Cannot Invoke `upgrade_contract` with Governance For Another Chain", async () => {
            const implementation = await loadProgramBpf(
                ARTIFACTS_PATH,
                circleIntegration.upgradeAuthorityAddress(),
            );

            const vaa = await postGovVaa(
                connection,
                payer,
                guardians,
                2n,
                {
                    upgradeContract: {
                        targetChain: 2,
                        implementation,
                    },
                },
                {
                    coreBridgeAddress: WORMHOLE_CORE_BRIDGE_ADDRESS,
                },
            );

            const ix = await circleIntegration.upgradeContractIx({
                payer: payer.publicKey,
                vaa,
            });

            await expectIxErr(connection, [ix], [payer], "Error Code: GovernanceForAnotherChain");
        });

        it("Cannot Invoke `upgrade_contract` with Invalid Governance Action", async () => {
            const implementation = await loadProgramBpf(
                ARTIFACTS_PATH,
                circleIntegration.upgradeAuthorityAddress(),
            );

            const vaa = await postGovVaa(
                connection,
                payer,
                guardians,
                2n,
                {
                    registerEmitterAndDomain: {
                        targetChain: 1,
                        foreignChain: 2,
                        foreignEmitter: Array.from(
                            Buffer.from(
                                "000000000000000000000000deadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
                                "hex",
                            ),
                        ),
                        cctpDomain: 0,
                    },
                },
                {
                    coreBridgeAddress: WORMHOLE_CORE_BRIDGE_ADDRESS,
                },
            );

            const ix = await circleIntegration.upgradeContractIx({
                payer: payer.publicKey,
                vaa,
                buffer: implementation,
            });

            await expectIxErr(connection, [ix], [payer], "Error Code: InvalidGovernanceAction");
        });
    });
});

function setUpgradeAuthorityIx(accounts: {
    programId: PublicKey;
    currentAuthority: PublicKey;
    newAuthority: PublicKey;
}) {
    const { programId, currentAuthority, newAuthority } = accounts;
    return setBufferAuthorityIx({
        buffer: PublicKey.findProgramAddressSync(
            [programId.toBuffer()],
            BPF_LOADER_UPGRADEABLE_ID,
        )[0],
        currentAuthority,
        newAuthority,
    });
}

function setBufferAuthorityIx(accounts: {
    buffer: PublicKey;
    currentAuthority: PublicKey;
    newAuthority: PublicKey;
}) {
    const { buffer, currentAuthority, newAuthority } = accounts;
    return new TransactionInstruction({
        programId: BPF_LOADER_UPGRADEABLE_ID,
        keys: [
            {
                pubkey: buffer,
                isWritable: true,
                isSigner: false,
            },
            { pubkey: currentAuthority, isSigner: true, isWritable: false },
            { pubkey: newAuthority, isSigner: false, isWritable: false },
        ],
        data: Buffer.from([4, 0, 0, 0]),
    });
}
