export * from "./circle";
export * from "./consts";
export * from "./messages";
export * from "./state";
export * from "./wormhole";

import { BN, EventParser, Program, utils as anchorUtils } from "@coral-xyz/anchor";
import * as splToken from "@solana/spl-token";
import {
    AddressLookupTableAccount,
    Connection,
    PublicKey,
    SYSVAR_CLOCK_PUBKEY,
    SYSVAR_RENT_PUBKEY,
    SystemProgram,
    TransactionInstruction,
    VersionedTransactionResponse,
} from "@solana/web3.js";
import {
    IDL,
    WormholeCircleIntegrationSolana,
} from "../../target/types/wormhole_circle_integration_solana";
import {
    CctpMessage,
    CctpTokenBurnMessage,
    MessageTransmitterProgram,
    TokenMessengerMinterProgram,
} from "./circle";
import { BPF_LOADER_UPGRADEABLE_ID } from "./consts";
import { Custodian, RegisteredEmitter } from "./state";
import { Claim, VaaAccount } from "./wormhole";
import { PostedMessageData } from "@certusone/wormhole-sdk/lib/cjs/solana/wormhole";
import { Deposit } from "./messages";

export const PROGRAM_IDS = [
    "Wormho1eCirc1e1ntegration111111111111111111", // mainnet placeholder
    "wCCTPvsyeL9qYqbHTv3DUAyzEfYcyHoYw5c4mgcbBeW", // testnet
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
    coreBridgeProgram: PublicKey;
    tokenMessengerMinterProgram: PublicKey;
    messageTransmitterProgram: PublicKey;
    tokenProgram: PublicKey;
};

export type RedeemTokensWithPayloadAccounts = {
    custodian: PublicKey;
    claim: PublicKey;
    mintRecipientAuthority: PublicKey;
    mintRecipient: PublicKey;
    registeredEmitter: PublicKey;
    messageTransmitterAuthority: PublicKey;
    messageTransmitterConfig: PublicKey;
    usedNonces: PublicKey;
    tokenMessenger: PublicKey;
    remoteTokenMessenger: PublicKey;
    tokenMinter: PublicKey;
    localToken: PublicKey;
    tokenPair: PublicKey;
    tokenMessengerMinterCustodyToken: PublicKey;
    tokenMessengerMinterProgram: PublicKey;
    messageTransmitterProgram: PublicKey;
    tokenProgram: PublicKey;
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
        this.program = new Program(IDL, new PublicKey(this._programId), {
            connection,
        });
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
            tokenMessengerMinterSenderAuthority: tokenMessengerMinterProgram.senderAuthority(),
            tokenMessengerMinterProgram: tokenMessengerMinterProgram.ID,
            messageTransmitterAuthority: messageTransmitterProgram.authorityAddress(),
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

        // Determine claim PDA.
        const { chain, address, sequence } = vaaAcct.emitterInfo();
        const claim = Claim.address(this.ID, address, chain, sequence);

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
                claim,
                registeredEmitter,
                remoteTokenMessenger,
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

        // Determine claim PDA.
        const { chain, address, sequence } = vaaAcct.emitterInfo();
        const claim = Claim.address(this.ID, address, chain, sequence);

        const payload = vaaAcct.payload();

        return this.program.methods
            .upgradeContract()
            .accounts({
                payer,
                custodian: this.custodianAddress(),
                vaa,
                claim,
                upgradeAuthority: this.upgradeAuthorityAddress(),
                spill: payer,
                buffer: inputBuffer ?? new PublicKey(payload.subarray(-32)),
                programData: this.programDataAddress(),
                thisProgram: this.ID,
                rent: SYSVAR_RENT_PUBKEY,
                clock: SYSVAR_CLOCK_PUBKEY,
                bpfLoaderUpgradeableProgram: BPF_LOADER_UPGRADEABLE_ID,
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
            messageTransmitterProgram,
            tokenMessengerMinterProgram,
            tokenProgram,
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
            coreBridgeProgram,
            tokenMessengerMinterProgram,
            messageTransmitterProgram,
            tokenProgram,
        };
    }

    async transferTokensWithPayloadIx(
        accounts: {
            payer: PublicKey;
            mint: PublicKey;
            burnSource: PublicKey;
            coreMessage: PublicKey;
        },
        args: TransferTokensWithPayloadArgs,
    ): Promise<TransactionInstruction> {
        let { payer, burnSource, mint, coreMessage } = accounts;

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
            tokenMessengerMinterProgram,
            messageTransmitterProgram,
            tokenProgram,
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
                coreEmitterSequence,
                coreFeeCollector,
                tokenMessengerMinterSenderAuthority,
                messageTransmitterConfig,
                tokenMessenger,
                remoteTokenMessenger,
                tokenMinter,
                localToken,
                coreBridgeProgram,
                tokenMessengerMinterProgram,
                messageTransmitterProgram,
                tokenProgram,
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
        const { chain, address, sequence } = vaaAcct.emitterInfo();
        const claim = Claim.address(this.ID, address, chain, sequence);

        const messageTransmitterProgram = this.messageTransmitterProgram();
        const {
            authority: messageTransmitterAuthority,
            messageTransmitterConfig,
            usedNonces,
            tokenMessengerMinterProgram,
            tokenMessenger,
            remoteTokenMessenger,
            tokenMinter,
            localToken,
            tokenPair,
            custodyToken: tokenMessengerMinterCustodyToken,
            tokenProgram,
        } = messageTransmitterProgram.receiveMessageAccounts(mint, msg);

        return {
            custodian: this.custodianAddress(),
            claim,
            mintRecipientAuthority,
            mintRecipient,
            registeredEmitter: this.registeredEmitterAddress(chain),
            messageTransmitterAuthority,
            messageTransmitterConfig,
            usedNonces,
            tokenMessenger,
            remoteTokenMessenger,
            tokenMinter,
            localToken,
            tokenPair,
            tokenMessengerMinterCustodyToken,
            tokenMessengerMinterProgram,
            messageTransmitterProgram: messageTransmitterProgram.ID,
            tokenProgram,
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
            claim,
            mintRecipientAuthority,
            mintRecipient,
            registeredEmitter,
            messageTransmitterAuthority,
            messageTransmitterConfig,
            usedNonces,
            tokenMessenger,
            remoteTokenMessenger,
            tokenMinter,
            localToken,
            tokenPair,
            tokenMessengerMinterCustodyToken,
            tokenMessengerMinterProgram,
            messageTransmitterProgram,
            tokenProgram,
        } = await this.redeemTokensWithPayloadAccounts(vaa, encodedCctpMessage);

        return this.program.methods
            .redeemTokensWithPayload(args)
            .accounts({
                payer,
                custodian,
                vaa,
                claim,
                mintRecipientAuthority: inputMintRecipientAuthority ?? mintRecipientAuthority,
                mintRecipient,
                registeredEmitter,
                messageTransmitterAuthority,
                messageTransmitterConfig,
                usedNonces,
                tokenMessenger,
                remoteTokenMessenger,
                tokenMinter,
                localToken,
                tokenPair,
                tokenMessengerMinterCustodyToken,
                tokenMessengerMinterProgram,
                messageTransmitterProgram,
                tokenProgram,
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

    async parseTransactionReceipt(
        txReceipt: VersionedTransactionResponse,
        addressLookupTableAccounts?: AddressLookupTableAccount[],
    ): Promise<SolanaWormholeCctpTxData[]> {
        if (txReceipt.meta === null) {
            throw new Error("meta not found in tx");
        }

        const txMeta = txReceipt.meta;
        if (txMeta.logMessages === undefined || txMeta.logMessages === null) {
            throw new Error("logMessages not found in tx");
        }

        const txLogMessages = txMeta.logMessages;

        // Decode message field from MessageSent event.
        const messageTransmitterProgram = this.messageTransmitterProgram();
        const parser = new EventParser(
            messageTransmitterProgram.ID,
            messageTransmitterProgram.program.coder,
        );

        // Map these puppies based on nonce.
        const encodedCctpMessages = new Map<bigint, Buffer>();
        for (const parsed of parser.parseLogs(txLogMessages, false)) {
            const msg = parsed.data.message as Buffer;
            encodedCctpMessages.set(CctpMessage.decode(msg).cctp.nonce, msg);
        }

        const fetchedKeys = txReceipt.transaction.message.getAccountKeys({
            addressLookupTableAccounts,
        });
        const accountKeys = fetchedKeys.staticAccountKeys;
        if (fetchedKeys.accountKeysFromLookups !== undefined) {
            accountKeys.push(
                ...fetchedKeys.accountKeysFromLookups.writable,
                ...fetchedKeys.accountKeysFromLookups.readonly,
            );
        }

        const coreBridgeProgramIndex = accountKeys.findIndex((key) =>
            key.equals(this.coreBridgeProgramId()),
        );
        const tokenMessengerMinterProgramIndex = accountKeys.findIndex((key) =>
            key.equals(this.tokenMessengerMinterProgram().ID),
        );
        const messageTransmitterProgramIndex = accountKeys.findIndex((key) =>
            key.equals(this.messageTransmitterProgram().ID),
        );
        if (
            coreBridgeProgramIndex == -1 &&
            tokenMessengerMinterProgramIndex == -1 &&
            messageTransmitterProgramIndex == -1
        ) {
            return [];
        }

        if (txMeta.innerInstructions === undefined || txMeta.innerInstructions === null) {
            throw new Error("innerInstructions not found in tx");
        }
        const txInnerInstructions = txMeta.innerInstructions;

        const custodian = this.custodianAddress();
        const postedMessageKeys: PublicKey[] = [];
        for (const innerIx of txInnerInstructions) {
            // Traverse instructions to find messages posted by the Wormhole Circle Integration program.
            for (const ixInfo of innerIx.instructions) {
                if (
                    ixInfo.programIdIndex == coreBridgeProgramIndex &&
                    anchorUtils.bytes.bs58.decode(ixInfo.data)[0] == 1 &&
                    accountKeys[ixInfo.accounts[2]].equals(custodian)
                ) {
                    postedMessageKeys.push(accountKeys[ixInfo.accounts[1]]);
                }
            }
        }

        return this.program.provider.connection
            .getMultipleAccountsInfo(postedMessageKeys)
            .then((infos) =>
                infos.map((info, i) => {
                    if (info === null) {
                        throw new Error("message info is null");
                    }
                    const payload = info.data.subarray(95);
                    const nonce = Deposit.decode(payload).deposit.cctpNonce;
                    const encodedCctpMessage = encodedCctpMessages.get(nonce);
                    if (encodedCctpMessage === undefined) {
                        throw new Error(
                            `cannot find CCTP message with nonce ${nonce} in tx receipt`,
                        );
                    }

                    return {
                        coreMessageAccount: postedMessageKeys[i],
                        coreMessageSequence: info.data.readBigUInt64LE(49),
                        encodedCctpMessage,
                    };
                }),
            );
    }
}

export function mainnet(): ProgramId {
    return "Wormho1eCirc1e1ntegration111111111111111111";
}

export function testnet(): ProgramId {
    return "wCCTPvsyeL9qYqbHTv3DUAyzEfYcyHoYw5c4mgcbBeW";
}
