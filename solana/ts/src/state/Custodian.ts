import { PublicKey } from "@solana/web3.js";

export class Custodian {
    bump: number;
    upgradeAuthorityBump: number;

    constructor(bump: number, upgradeAuthorityBump: number) {
        this.bump = bump;
        this.upgradeAuthorityBump = upgradeAuthorityBump;
    }

    static address(programId: PublicKey): PublicKey {
        return PublicKey.findProgramAddressSync([Buffer.from("emitter")], programId)[0];
    }
}
