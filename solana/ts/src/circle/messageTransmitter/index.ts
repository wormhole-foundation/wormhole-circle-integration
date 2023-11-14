import { Program } from "@coral-xyz/anchor";
import { TOKEN_PROGRAM_ID } from "@solana/spl-token";
import { Connection, PublicKey } from "@solana/web3.js";
import { CctpTokenBurnMessage } from "../messages";
import { TokenMessengerMinterProgram } from "../tokenMessengerMinter";
import { IDL, MessageTransmitter } from "../types/message_transmitter";
import { MessageTransmitterConfig } from "./MessageTransmitterConfig";
import { UsedNonses } from "./UsedNonces";

export const PROGRAM_IDS = ["CCTPmbSD7gX1bxKPAmg77w8oFzNFpaQiQUWD43TKaecd"] as const;

export type ProgramId = (typeof PROGRAM_IDS)[number];

export type ReceiveMessageAccounts = {
    authority: PublicKey;
    messageTransmitterConfig: PublicKey;
    usedNonces: PublicKey;
    tokenMessengerMinterProgram: PublicKey;
    tokenMessenger: PublicKey;
    remoteTokenMessenger: PublicKey;
    tokenMinter: PublicKey;
    localToken: PublicKey;
    tokenPair: PublicKey;
    custodyToken: PublicKey;
    tokenProgram: PublicKey;
};

export class MessageTransmitterProgram {
    private _programId: ProgramId;

    program: Program<MessageTransmitter>;

    constructor(connection: Connection, programId?: ProgramId) {
        this._programId = programId ?? testnet();
        this.program = new Program(IDL, new PublicKey(this._programId), {
            connection,
        });
    }

    get ID(): PublicKey {
        return this.program.programId;
    }

    messageTransmitterConfigAddress(): PublicKey {
        return MessageTransmitterConfig.address(this.ID);
    }

    async fetchMessageTransmitterConfig(addr: PublicKey): Promise<MessageTransmitterConfig> {
        const {
            owner,
            pendingOwner,
            attesterManager,
            pauser,
            paused,
            localDomain,
            version,
            signatureThreshold,
            enabledAttesters,
            maxMessageBodySize,
            nextAvailableNonce,
            authorityBump,
        } = await this.program.account.messageTransmitter.fetch(addr);

        return new MessageTransmitterConfig(
            owner,
            pendingOwner,
            attesterManager,
            pauser,
            paused,
            localDomain,
            version,
            signatureThreshold,
            enabledAttesters.map((addr) => Array.from(addr.toBuffer())),
            BigInt(maxMessageBodySize.toString()),
            BigInt(nextAvailableNonce.toString()),
            authorityBump,
        );
    }

    usedNoncesAddress(remoteDomain: number, nonce: bigint): PublicKey {
        return UsedNonses.address(this.ID, remoteDomain, nonce);
    }

    authorityAddress(): PublicKey {
        return PublicKey.findProgramAddressSync(
            [Buffer.from("message_transmitter_authority")],
            this.ID,
        )[0];
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

    receiveMessageAccounts(
        mint: PublicKey,
        circleMessage: CctpTokenBurnMessage | Buffer,
    ): ReceiveMessageAccounts {
        const {
            cctp: { sourceDomain, nonce },
            burnTokenAddress,
        } = CctpTokenBurnMessage.from(circleMessage);

        const tokenMessengerMinterProgram = this.tokenMessengerMinterProgram();
        return {
            authority: this.authorityAddress(),
            messageTransmitterConfig: this.messageTransmitterConfigAddress(),
            usedNonces: this.usedNoncesAddress(sourceDomain, nonce),
            tokenMessengerMinterProgram: tokenMessengerMinterProgram.ID,
            tokenMessenger: tokenMessengerMinterProgram.tokenMessengerAddress(),
            remoteTokenMessenger:
                tokenMessengerMinterProgram.remoteTokenMessengerAddress(sourceDomain),
            tokenMinter: tokenMessengerMinterProgram.tokenMinterAddress(),
            localToken: tokenMessengerMinterProgram.localTokenAddress(mint),
            tokenPair: tokenMessengerMinterProgram.tokenPairAddress(sourceDomain, burnTokenAddress),
            custodyToken: tokenMessengerMinterProgram.custodyTokenAddress(mint),
            tokenProgram: TOKEN_PROGRAM_ID,
        };
    }
}

export function mainnet(): ProgramId {
    return "CCTPmbSD7gX1bxKPAmg77w8oFzNFpaQiQUWD43TKaecd";
}

export function testnet(): ProgramId {
    return "CCTPmbSD7gX1bxKPAmg77w8oFzNFpaQiQUWD43TKaecd";
}
