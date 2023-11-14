import { PublicKey } from "@solana/web3.js";

export const GUARDIAN_KEY = "cfb12303a19cde580bb4dd771639b0d26bc68353645571a8cff516ab2ee113a0";

export const PAYER_PRIVATE_KEY = Buffer.from(
    "7037e963e55b4455cf3f0a2e670031fa16bd1ea79d921a94af9bd46856b6b9c00c1a5886fe1093df9fc438c296f9f7275b7718b6bc0e156d8d336c58f083996d",
    "hex",
);

export const WORMHOLE_CORE_BRIDGE_ADDRESS = new PublicKey(
    "worm2ZoG2kUd4vFXhvjh93UUH596ayRfgQ2MgjNMTth",
);

export const USDC_MINT_ADDRESS = new PublicKey("4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU");

export const ETHEREUM_WORMHOLE_CCTP_ADDRESS = "0x0a69146716b3a21622287efa1607424c663069a4";
export const ETHEREUM_USDC_ADDRESS = "0x07865c6e87b9f70255377e024ace6630c1eaa37f";
