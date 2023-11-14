import { ethers } from "ethers";

export type DepositHeader = {
    tokenAddress: Array<number>;
    amount: bigint;
    sourceCctpDomain: number;
    destinationCctpDomain: number;
    cctpNonce: bigint;
    burnSource: Array<number>;
    mintRecipient: Array<number>;
    payloadLen: number;
};

export class Deposit {
    deposit: DepositHeader;
    payload: Buffer;

    constructor(deposit: DepositHeader, payload: Buffer) {
        this.deposit = deposit;
        this.payload = payload;
    }

    static decode(buf: Buffer): Deposit {
        if (buf.readUInt8(0) != 1) {
            throw new Error("Invalid Wormhole CCTP deposit message");
        }
        buf = buf.subarray(1);

        const tokenAddress = Array.from(buf.subarray(0, 32));
        const amount = BigInt(ethers.BigNumber.from(buf.subarray(32, 64)).toString());
        const sourceCctpDomain = buf.readUInt32BE(64);
        const destinationCctpDomain = buf.readUInt32BE(68);
        const cctpNonce = buf.readBigUint64BE(72);
        const burnSource = Array.from(buf.subarray(80, 112));
        const mintRecipient = Array.from(buf.subarray(112, 144));
        const payloadLen = buf.readUInt16BE(144);
        const payload = buf.subarray(146, 146 + payloadLen);

        return new Deposit(
            {
                tokenAddress,
                amount,
                sourceCctpDomain,
                destinationCctpDomain,
                cctpNonce,
                burnSource,
                mintRecipient,
                payloadLen,
            },
            payload,
        );
    }

    encode(): Buffer {
        const buf = Buffer.alloc(146);

        const { deposit, payload } = this;
        const {
            tokenAddress,
            amount,
            sourceCctpDomain,
            destinationCctpDomain,
            cctpNonce,
            burnSource,
            mintRecipient,
            payloadLen,
        } = deposit;

        let offset = 0;
        buf.set(tokenAddress, offset);
        offset += 32;

        // Special handling w/ uint256. This value will most likely encoded in < 32 bytes, so we
        // jump ahead by 32 and subtract the length of the encoded value.
        const encodedAmount = ethers.utils.arrayify(ethers.BigNumber.from(amount.toString()));
        buf.set(encodedAmount, (offset += 32) - encodedAmount.length);

        offset = buf.writeUInt32BE(sourceCctpDomain, offset);
        offset = buf.writeUInt32BE(destinationCctpDomain, offset);
        offset = buf.writeBigUInt64BE(cctpNonce, offset);
        buf.set(burnSource, offset);
        offset += 32;
        buf.set(mintRecipient, offset);
        offset += 32;
        offset = buf.writeUInt16BE(payloadLen, offset);

        return Buffer.concat([Buffer.alloc(1, 1), buf, payload]);
    }
}
