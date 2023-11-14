import { PublicKey } from "@solana/web3.js";

export class RegisteredEmitter {
    bump: number;
    cctpDomain: number;
    chain: number;
    address: Array<number>;

    constructor(bump: number, cctpDomain: number, chain: number, address: Array<number>) {
        this.bump = bump;
        this.cctpDomain = cctpDomain;
        this.chain = chain;
        this.address = address;
    }

    static address(programId: PublicKey, chain: number): PublicKey {
        const encodedChain = Buffer.alloc(2);
        encodedChain.writeUInt16BE(chain, 0);
        return PublicKey.findProgramAddressSync(
            [Buffer.from("registered_emitter"), encodedChain],
            programId,
        )[0];
    }
}
