export * from "./cctp";
export * from "./consts";
export * from "./messages";
export * from "./state";
export * from "./wormhole";

import { BN, Program } from "@coral-xyz/anchor";
import * as splToken from "@solana/spl-token";
import {
    Connection,
    PublicKey,
    SYSVAR_CLOCK_PUBKEY,
    SYSVAR_RENT_PUBKEY,
    SystemProgram,
    TransactionInstruction,
} from "@solana/web3.js";
import { WormholeCircleIntegrationSolana } from "../../target/types/wormhole_circle_integration_solana";
import * as IDL from "../../target/idl/wormhole_circle_integration_solana.json";
import {
    CctpTokenBurnMessage,
    MessageTransmitterProgram,
    TokenMessengerMinterProgram,
} from "./cctp";
import { BPF_LOADER_UPGRADEABLE_ID } from "./consts";
import { ConsumedVaa, Custodian, RegisteredEmitter } from "./state";
import { VaaAccount } from "./wormhole";

export const PROGRAM_IDS = [
    "Wormho1eCirc1e1ntegration111111111111111111", // mainnet placeholder
    "wcihrWf1s91vfukW7LW8ZvR1rzpeZ9BrtZ8oyPkWK5d", // testnet
] as const;

export type ProgramId = (typeof PROGRAM_IDS)[number];

export type TransferTokensWithPayloadArgs = {
    amount: bigint;
    targetChain: number;
    mintRecipient: Array<number>;
    wormholeMessageNonce: number;
    payload: Buffer;
};

export type PublishMessageAccounts = {
    coreBridgeConfig: PublicKey;
    coreEmitterSequence: PublicKey;
    coreFeeCollector: PublicKey;
    coreBridgeProgram: PublicKey;
};

export type WormholeCctpCommonAccounts = PublishMessageAccounts & {
    wormholeCctpProgram: PublicKey;
    systemProgram: PublicKey;
    rent: PublicKey;
    custodian: PublicKey;
    custodyToken: PublicKey;
    tokenMessenger: PublicKey;
    tokenMinter: PublicKey;
    tokenMessengerMinterSenderAuthority: PublicKey;
    tokenMessengerMinterProgram: PublicKey;
    messageTransmitterAuthority: PublicKey;
    messageTransmitterConfig: PublicKey;
    messageTransmitterProgram: PublicKey;
    tokenProgram: PublicKey;
    mint?: PublicKey;
    localToken?: PublicKey;
    tokenMessengerMinterCustodyToken?: PublicKey;
};

export type TransferTokensWithPayloadAccounts = PublishMessageAccounts & {
    custodian: PublicKey;
    custodyToken: PublicKey;
    registeredEmitter: PublicKey;
    tokenMessengerMinterSenderAuthority: PublicKey;
    messageTransmitterConfig: PublicKey;
    tokenMessenger: PublicKey;
    remoteTokenMessenger: PublicKey;
    tokenMinter: PublicKey;
    localToken: PublicKey;
    tokenMessengerMinterEventAuthority: PublicKey;
    coreBridgeProgram: PublicKey;
    tokenMessengerMinterProgram: PublicKey;
    messageTransmitterProgram: PublicKey;
};

export type RedeemTokensWithPayloadAccounts = {
    custodian: PublicKey;
    consumedVaa: PublicKey;
    mintRecipientAuthority: PublicKey;
    mintRecipient: PublicKey;
    registeredEmitter: PublicKey;
    messageTransmitterAuthority: PublicKey;
    messageTransmitterConfig: PublicKey;
    usedNonces: PublicKey;
    messageTransmitterEventAuthority: PublicKey;
    tokenMessenger: PublicKey;
    remoteTokenMessenger: PublicKey;
    tokenMinter: PublicKey;
    localToken: PublicKey;
    tokenPair: PublicKey;
    tokenMessengerMinterCustodyToken: PublicKey;
    tokenMessengerMinterEventAuthority: PublicKey;
    tokenMessengerMinterProgram: PublicKey;
    messageTransmitterProgram: PublicKey;
};

export type SolanaWormholeCctpTxData = {
    coreMessageAccount: PublicKey;
    coreMessageSequence: bigint;
    encodedCctpMessage: Buffer;
};

export class CircleIntegrationProgram {
    private _programId: ProgramId;

    program: Program<WormholeCircleIntegrationSolana>;

    constructor(connection: Connection, programId?: ProgramId) {
        this._programId = programId ?? testnet();
        this.program = new Program(
            { ...(IDL as any), address: this._programId },
            {
                connection,
            },
        );
    }

    get ID(): PublicKey {
        return this.program.programId;
    }

    upgradeAuthorityAddress(): PublicKey {
        return PublicKey.findProgramAddressSync([Buffer.from("upgrade")], this.ID)[0];
    }

    programDataAddress(): PublicKey {
        return PublicKey.findProgramAddressSync([this.ID.toBuffer()], BPF_LOADER_UPGRADEABLE_ID)[0];
    }

    custodianAddress(): PublicKey {
        return Custodian.address(this.ID);
    }

    async fetchCustodian(addr: PublicKey): Promise<Custodian> {
        const { bump, upgradeAuthorityBump } = await this.program.account.custodian.fetch(addr);
        return new Custodian(bump, upgradeAuthorityBump);
    }

    registeredEmitterAddress(chain: number): PublicKey {
        return RegisteredEmitter.address(this.ID, chain);
    }

    async fetchRegisteredEmitter(addr: PublicKey): Promise<RegisteredEmitter> {
        const {
            bump,
            chain: registeredChain,
            cctpDomain,
            address,
        } = await this.program.account.registeredEmitter.fetch(addr);
        return new RegisteredEmitter(bump, cctpDomain, registeredChain, address);
    }

    custodyTokenAccountAddress(): PublicKey {
        return PublicKey.findProgramAddressSync([Buffer.from("custody")], this.ID)[0];
    }

    consumedVaaAddress(vaaHash: Array<number> | Uint8Array): PublicKey {
        return ConsumedVaa.address(this.ID, vaaHash);
    }

    commonAccounts(mint?: PublicKey): WormholeCctpCommonAccounts {
        const custodian = this.custodianAddress();
        const { coreBridgeConfig, coreEmitterSequence, coreFeeCollector, coreBridgeProgram } =
            this.publishMessageAccounts(custodian);

        const tokenMessengerMinterProgram = this.tokenMessengerMinterProgram();
        const messageTransmitterProgram = this.messageTransmitterProgram();

        const [localToken, tokenMessengerMinterCustodyToken] = (() => {
            if (mint === undefined) {
                return [undefined, undefined];
            } else {
                return [
                    tokenMessengerMinterProgram.localTokenAddress(mint),
                    tokenMessengerMinterProgram.custodyTokenAddress(mint),
                ];
            }
        })();

        return {
            wormholeCctpProgram: this.ID,
            systemProgram: SystemProgram.programId,
            rent: SYSVAR_RENT_PUBKEY,
            custodian,
            custodyToken: this.custodyTokenAccountAddress(),
            coreBridgeConfig,
            coreEmitterSequence,
            coreFeeCollector,
            coreBridgeProgram,
            tokenMessenger: tokenMessengerMinterProgram.tokenMessengerAddress(),
            tokenMinter: tokenMessengerMinterProgram.tokenMinterAddress(),
            tokenMessengerMinterSenderAuthority:
                tokenMessengerMinterProgram.senderAuthorityAddress(),
            tokenMessengerMinterProgram: tokenMessengerMinterProgram.ID,
            messageTransmitterAuthority: messageTransmitterProgram.authorityAddress(
                tokenMessengerMinterProgram.ID,
            ),
            messageTransmitterConfig: messageTransmitterProgram.messageTransmitterConfigAddress(),
            messageTransmitterProgram: messageTransmitterProgram.ID,
            tokenProgram: splToken.TOKEN_PROGRAM_ID,
            mint,
            localToken,
            tokenMessengerMinterCustodyToken,
        };
    }

    async initializeIx(deployer: PublicKey): Promise<TransactionInstruction> {
        return this.program.methods
            .initialize()
            .accounts({
                deployer,
                custodian: this.custodianAddress(),
                upgradeAuthority: this.upgradeAuthorityAddress(),
                programData: this.programDataAddress(),
                bpfLoaderUpgradeableProgram: BPF_LOADER_UPGRADEABLE_ID,
                systemProgram: SystemProgram.programId,
            })
            .instruction();
    }

    async registerEmitterAndDomainIx(accounts: {
        payer: PublicKey;
        vaa: PublicKey;
        remoteTokenMessenger?: PublicKey;
    }): Promise<TransactionInstruction> {
        const { payer, vaa, remoteTokenMessenger: inputRemoteTokenMessenger } = accounts;

        const vaaAcct = await VaaAccount.fetch(this.program.provider.connection, vaa);
        const payload = vaaAcct.payload();
        const registeredEmitter = this.registeredEmitterAddress(payload.readUInt16BE(35));
        const remoteTokenMessenger = (() => {
            if (payload.length >= 73) {
                const cctpDomain = payload.readUInt32BE(69);
                return this.tokenMessengerMinterProgram().remoteTokenMessengerAddress(cctpDomain);
            } else if (inputRemoteTokenMessenger !== undefined) {
                return inputRemoteTokenMessenger;
            } else {
                throw new Error("remoteTokenMessenger must be provided");
            }
        })();

        return this.program.methods
            .registerEmitterAndDomain()
            .accounts({
                payer,
                custodian: this.custodianAddress(),
                vaa,
                consumedVaa: this.consumedVaaAddress(vaaAcct.digest()),
                registeredEmitter,
                remoteTokenMessenger,
                systemProgram: SystemProgram.programId,
            })
            .instruction();
    }

    async upgradeContractIx(accounts: {
        payer: PublicKey;
        vaa: PublicKey;
        buffer?: PublicKey;
    }): Promise<TransactionInstruction> {
        const { payer, vaa, buffer: inputBuffer } = accounts;

        const vaaAcct = await VaaAccount.fetch(this.program.provider.connection, vaa);
        const payload = vaaAcct.payload();

        return this.program.methods
            .upgradeContract()
            .accounts({
                payer,
                custodian: this.custodianAddress(),
                vaa,
                consumedVaa: this.consumedVaaAddress(vaaAcct.digest()),
                upgradeAuthority: this.upgradeAuthorityAddress(),
                spill: payer,
                buffer: inputBuffer ?? new PublicKey(payload.subarray(-32)),
                programData: this.programDataAddress(),
                thisProgram: this.ID,
                rent: SYSVAR_RENT_PUBKEY,
                clock: SYSVAR_CLOCK_PUBKEY,
                bpfLoaderUpgradeableProgram: BPF_LOADER_UPGRADEABLE_ID,
                systemProgram: SystemProgram.programId,
            })
            .instruction();
    }

    async transferTokensWithPayloadAccounts(
        mint: PublicKey,
        targetChain: number,
    ): Promise<TransferTokensWithPayloadAccounts> {
        const registeredEmitter = this.registeredEmitterAddress(targetChain);
        const remoteDomain = await this.fetchRegisteredEmitter(registeredEmitter).then(
            (acct) => acct.cctpDomain,
        );

        const {
            senderAuthority: tokenMessengerMinterSenderAuthority,
            messageTransmitterConfig,
            tokenMessenger,
            remoteTokenMessenger,
            tokenMinter,
            localToken,
            tokenMessengerMinterEventAuthority,
            messageTransmitterProgram,
            tokenMessengerMinterProgram,
        } = this.tokenMessengerMinterProgram().depositForBurnWithCallerAccounts(mint, remoteDomain);

        const custodian = this.custodianAddress();
        const { coreBridgeConfig, coreEmitterSequence, coreFeeCollector, coreBridgeProgram } =
            this.publishMessageAccounts(custodian);

        return {
            custodian,
            custodyToken: this.custodyTokenAccountAddress(),
            registeredEmitter,
            coreBridgeConfig,
            coreEmitterSequence,
            coreFeeCollector,
            tokenMessengerMinterSenderAuthority,
            messageTransmitterConfig,
            tokenMessenger,
            remoteTokenMessenger,
            tokenMinter,
            localToken,
            tokenMessengerMinterEventAuthority,
            coreBridgeProgram,
            tokenMessengerMinterProgram,
            messageTransmitterProgram,
        };
    }

    async transferTokensWithPayloadIx(
        accounts: {
            payer: PublicKey;
            mint: PublicKey;
            burnSource: PublicKey;
            coreMessage: PublicKey;
            cctpMessage: PublicKey;
        },
        args: TransferTokensWithPayloadArgs,
    ): Promise<TransactionInstruction> {
        let { payer, burnSource, mint, coreMessage, cctpMessage } = accounts;

        const { amount, targetChain, mintRecipient, wormholeMessageNonce, payload } = args;

        const {
            custodian,
            custodyToken,
            registeredEmitter,
            coreBridgeConfig,
            coreEmitterSequence,
            coreFeeCollector,
            coreBridgeProgram,
            tokenMessengerMinterSenderAuthority,
            messageTransmitterConfig,
            tokenMessenger,
            remoteTokenMessenger,
            tokenMinter,
            localToken,
            tokenMessengerMinterEventAuthority,
            tokenMessengerMinterProgram,
            messageTransmitterProgram,
        } = await this.transferTokensWithPayloadAccounts(mint, targetChain);

        return this.program.methods
            .transferTokensWithPayload({
                amount: new BN(amount.toString()),
                mintRecipient,
                wormholeMessageNonce,
                payload,
            })
            .accounts({
                payer,
                custodian,
                mint,
                burnSource,
                custodyToken,
                registeredEmitter,
                coreBridgeConfig,
                coreMessage,
                cctpMessage,
                coreEmitterSequence,
                coreFeeCollector,
                tokenMessengerMinterSenderAuthority,
                messageTransmitterConfig,
                tokenMessenger,
                remoteTokenMessenger,
                tokenMinter,
                localToken,
                tokenMessengerMinterEventAuthority,
                coreBridgeProgram,
                tokenMessengerMinterProgram,
                messageTransmitterProgram,
                systemProgram: SystemProgram.programId,
                tokenProgram: splToken.TOKEN_PROGRAM_ID,
                rent: SYSVAR_RENT_PUBKEY,
                clock: SYSVAR_CLOCK_PUBKEY,
            })
            .instruction();
    }

    async redeemTokensWithPayloadAccounts(
        vaa: PublicKey,
        circleMessage: CctpTokenBurnMessage | Buffer,
    ): Promise<RedeemTokensWithPayloadAccounts> {
        const msg = CctpTokenBurnMessage.from(circleMessage);
        const mintRecipient = new PublicKey(msg.mintRecipient);
        const [mint, mintRecipientAuthority] = await splToken
            .getAccount(this.program.provider.connection, mintRecipient)
            .then((token) => [token.mint, token.owner]);

        // Determine claim PDA.
        const vaaAcct = await VaaAccount.fetch(this.program.provider.connection, vaa);
        const { chain } = vaaAcct.emitterInfo();

        const {
            authority: messageTransmitterAuthority,
            messageTransmitterConfig,
            usedNonces,
            tokenMessengerMinterProgram,
            messageTransmitterEventAuthority,
            messageTransmitterProgram,
            tokenMessenger,
            remoteTokenMessenger,
            tokenMinter,
            localToken,
            tokenPair,
            custodyToken: tokenMessengerMinterCustodyToken,
            eventAuthority: tokenMessengerMinterEventAuthority,
        } = this.messageTransmitterProgram().receiveTokenMessengerMinterMessageAccounts(mint, msg);

        return {
            custodian: this.custodianAddress(),
            consumedVaa: this.consumedVaaAddress(vaaAcct.digest()),
            mintRecipientAuthority,
            mintRecipient,
            registeredEmitter: this.registeredEmitterAddress(chain),
            messageTransmitterAuthority,
            messageTransmitterConfig,
            usedNonces,
            messageTransmitterEventAuthority,
            tokenMessenger,
            remoteTokenMessenger,
            tokenMinter,
            localToken,
            tokenPair,
            tokenMessengerMinterCustodyToken,
            tokenMessengerMinterEventAuthority,
            tokenMessengerMinterProgram,
            messageTransmitterProgram,
        };
    }

    async redeemTokensWithPayloadIx(
        accounts: {
            payer: PublicKey;
            vaa: PublicKey;
            mintRecipientAuthority?: PublicKey;
        },
        args: {
            encodedCctpMessage: Buffer;
            cctpAttestation: Buffer;
        },
    ): Promise<TransactionInstruction> {
        const { payer, vaa, mintRecipientAuthority: inputMintRecipientAuthority } = accounts;

        const { encodedCctpMessage } = args;

        const {
            custodian,
            consumedVaa,
            mintRecipientAuthority,
            mintRecipient,
            registeredEmitter,
            messageTransmitterAuthority,
            messageTransmitterConfig,
            usedNonces,
            messageTransmitterEventAuthority,
            tokenMessenger,
            remoteTokenMessenger,
            tokenMinter,
            localToken,
            tokenPair,
            tokenMessengerMinterCustodyToken,
            tokenMessengerMinterEventAuthority,
            tokenMessengerMinterProgram,
            messageTransmitterProgram,
        } = await this.redeemTokensWithPayloadAccounts(vaa, encodedCctpMessage);

        return this.program.methods
            .redeemTokensWithPayload(args)
            .accounts({
                payer,
                custodian,
                vaa,
                consumedVaa,
                mintRecipientAuthority: inputMintRecipientAuthority ?? mintRecipientAuthority,
                mintRecipient,
                registeredEmitter,
                messageTransmitterAuthority,
                messageTransmitterConfig,
                usedNonces,
                messageTransmitterEventAuthority,
                tokenMessenger,
                remoteTokenMessenger,
                tokenMinter,
                localToken,
                tokenPair,
                tokenMessengerMinterCustodyToken,
                tokenMessengerMinterEventAuthority,
                tokenMessengerMinterProgram,
                messageTransmitterProgram,
                systemProgram: SystemProgram.programId,
                tokenProgram: splToken.TOKEN_PROGRAM_ID,
            })
            .instruction();
    }

    tokenMessengerMinterProgram(): TokenMessengerMinterProgram {
        switch (this._programId) {
            case testnet(): {
                return new TokenMessengerMinterProgram(
                    this.program.provider.connection,
                    "CCTPiPYPc6AsJuwueEnWgSgucamXDZwBd53dQ11YiKX3",
                );
            }
            case mainnet(): {
                return new TokenMessengerMinterProgram(
                    this.program.provider.connection,
                    "CCTPiPYPc6AsJuwueEnWgSgucamXDZwBd53dQ11YiKX3",
                );
            }
            default: {
                throw new Error("unsupported network");
            }
        }
    }

    messageTransmitterProgram(): MessageTransmitterProgram {
        switch (this._programId) {
            case testnet(): {
                return new MessageTransmitterProgram(
                    this.program.provider.connection,
                    "CCTPmbSD7gX1bxKPAmg77w8oFzNFpaQiQUWD43TKaecd",
                );
            }
            case mainnet(): {
                return new MessageTransmitterProgram(
                    this.program.provider.connection,
                    "CCTPmbSD7gX1bxKPAmg77w8oFzNFpaQiQUWD43TKaecd",
                );
            }
            default: {
                throw new Error("unsupported network");
            }
        }
    }

    publishMessageAccounts(emitter: PublicKey): PublishMessageAccounts {
        const coreBridgeProgram = this.coreBridgeProgramId();

        return {
            coreBridgeConfig: PublicKey.findProgramAddressSync(
                [Buffer.from("Bridge")],
                coreBridgeProgram,
            )[0],
            coreEmitterSequence: PublicKey.findProgramAddressSync(
                [Buffer.from("Sequence"), emitter.toBuffer()],
                coreBridgeProgram,
            )[0],
            coreFeeCollector: PublicKey.findProgramAddressSync(
                [Buffer.from("fee_collector")],
                coreBridgeProgram,
            )[0],
            coreBridgeProgram,
        };
    }

    coreBridgeProgramId(): PublicKey {
        switch (this._programId) {
            case testnet(): {
                return new PublicKey("3u8hJUVTA4jH1wYAyUur7FFZVQ8H635K3tSHHF4ssjQ5");
            }
            case mainnet(): {
                return new PublicKey("worm2ZoG2kUd4vFXhvjh93UUH596ayRfgQ2MgjNMTth");
            }
            default: {
                throw new Error("unsupported network");
            }
        }
    }
}

export function mainnet(): ProgramId {
    return "Wormho1eCirc1e1ntegration111111111111111111";
}

export function testnet(): ProgramId {
    return "wcihrWf1s91vfukW7LW8ZvR1rzpeZ9BrtZ8oyPkWK5d";
}
