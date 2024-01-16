import { ethers } from "ethers";

export interface TransferParameters {
    token: string;
    amount: ethers.BigNumber;
    targetChain: number;
    mintRecipient: Uint8Array;
}

export interface RedeemParameters {
    encodedWormholeMessage: Uint8Array;
    circleBridgeMessage: Uint8Array;
    circleAttestation: Uint8Array;
}

export interface DepositWithPayload {
    token: Buffer;
    amount: ethers.BigNumber;
    sourceDomain: number;
    targetDomain: number;
    nonce: number;
    fromAddress: Buffer;
    mintRecipient: Buffer;
    payload: Buffer;
}
