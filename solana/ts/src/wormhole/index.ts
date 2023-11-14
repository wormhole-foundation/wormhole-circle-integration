import { parseVaa } from "@certusone/wormhole-sdk";
import { Connection, PublicKey } from "@solana/web3.js";

export type EncodedVaa = {
    status: number;
    writeAuthority: PublicKey;
    version: number;
    buf: Buffer;
};

export type PostedVaaV1 = {
    consistencyLevel: number;
    timestamp: number;
    signatureSet: PublicKey;
    guardianSetIndex: number;
    nonce: number;
    sequence: bigint;
    emitterChain: number;
    emitterAddress: Array<number>;
    payload: Buffer;
};

export type EmitterInfo = {
    chain: number;
    address: Array<number>;
    sequence: bigint;
};

export class VaaAccount {
    private _encodedVaa?: EncodedVaa;
    private _postedVaaV1?: PostedVaaV1;

    static async fetch(connection: Connection, addr: PublicKey): Promise<VaaAccount> {
        const data = await connection.getAccountInfo(addr).then((acct) => acct.data);
        if (data.subarray(0, 8).equals(Uint8Array.from([226, 101, 163, 4, 133, 160, 84, 245]))) {
            const status = data[8];
            const writeAuthority = new PublicKey(data.subarray(9, 41));
            const version = data[41];
            const bufLen = data.readUInt32LE(42);
            const buf = data.subarray(46, 46 + bufLen);

            return new VaaAccount({ encodedVaa: { status, writeAuthority, version, buf } });
        } else if (data.subarray(0, 4).equals(Uint8Array.from([118, 97, 97, 1]))) {
            const consistencyLevel = data[4];
            const timestamp = data.readUInt32LE(5);
            const signatureSet = new PublicKey(data.subarray(9, 41));
            const guardianSetIndex = data.readUInt32LE(41);
            const nonce = data.readUInt32LE(45);
            const sequence = data.readBigUInt64LE(49);
            const emitterChain = data.readUInt16LE(57);
            const emitterAddress = Array.from(data.subarray(59, 91));
            const payloadLen = data.readUInt32LE(91);
            const payload = data.subarray(95, 95 + payloadLen);

            return new VaaAccount({
                postedVaaV1: {
                    consistencyLevel,
                    timestamp,
                    signatureSet,
                    guardianSetIndex,
                    nonce,
                    sequence,
                    emitterChain,
                    emitterAddress,
                    payload,
                },
            });
        } else {
            throw new Error("invalid VAA account data");
        }
    }

    emitterInfo(): EmitterInfo {
        if (this._encodedVaa !== undefined) {
            const parsed = parseVaa(this._encodedVaa.buf);
            return {
                chain: parsed.emitterChain,
                address: Array.from(parsed.emitterAddress),
                sequence: parsed.sequence,
            };
        } else {
            const { emitterChain: chain, emitterAddress: address, sequence } = this._postedVaaV1;
            return {
                chain,
                address,
                sequence,
            };
        }
    }

    payload(): Buffer {
        if (this._encodedVaa !== undefined) {
            return parseVaa(this._encodedVaa.buf).payload;
        } else {
            return this._postedVaaV1.payload;
        }
    }

    get encodedVaa(): EncodedVaa {
        if (this._encodedVaa === undefined) {
            throw new Error("VaaAccount does not have encodedVaa");
        }
        return this._encodedVaa;
    }

    get postedVaaV1(): PostedVaaV1 {
        if (this._postedVaaV1 === undefined) {
            throw new Error("VaaAccount does not have postedVaaV1");
        }
        return this._postedVaaV1;
    }

    private constructor(data: { encodedVaa?: EncodedVaa; postedVaaV1?: PostedVaaV1 }) {
        const { encodedVaa, postedVaaV1 } = data;
        if (encodedVaa !== undefined && postedVaaV1 !== undefined) {
            throw new Error("VaaAccount cannot have both encodedVaa and postedVaaV1");
        }

        this._encodedVaa = encodedVaa;
        this._postedVaaV1 = postedVaaV1;
    }
}

export class Claim {
    static address(
        programId: PublicKey,
        address: Array<number>,
        chain: number,
        sequence: bigint,
        prefix?: Buffer,
    ): PublicKey {
        const chainBuf = Buffer.alloc(2);
        chainBuf.writeUInt16BE(chain);

        const sequenceBuf = Buffer.alloc(8);
        sequenceBuf.writeBigUInt64BE(sequence);

        if (prefix !== undefined) {
            return PublicKey.findProgramAddressSync(
                [prefix, Buffer.from(address), chainBuf, sequenceBuf],
                new PublicKey(programId),
            )[0];
        } else {
            return PublicKey.findProgramAddressSync(
                [Buffer.from(address), chainBuf, sequenceBuf],
                new PublicKey(programId),
            )[0];
        }
    }
}
