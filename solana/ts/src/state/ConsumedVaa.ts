import { PublicKey } from "@solana/web3.js";

export class ConsumedVaa {
    static address(programId: PublicKey, vaaHash: Array<number> | Uint8Array): PublicKey {
        return PublicKey.findProgramAddressSync(
            [Buffer.from("consumed-vaa"), Buffer.from(vaaHash)],
            new PublicKey(programId),
        )[0];
    }
}
