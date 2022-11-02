import { ethers } from "ethers";

// rpc
export const LOCALHOST = "http://localhost:8545";

// fork
export const FORK_CHAIN_ID = Number(process.env.TESTING_FORK_CHAIN_ID!);

// wormhole
export const WORMHOLE_ADDRESS = process.env.TESTING_WORMHOLE_ADDRESS!;
export const WORMHOLE_CHAIN_ID = Number(process.env.TESTING_WORMHOLE_CHAIN_ID!);
export const WORMHOLE_MESSAGE_FEE = ethers.BigNumber.from(
  process.env.TESTING_WORMHOLE_MESSAGE_FEE!
);
export const WORMHOLE_GUARDIAN_SET_INDEX = Number(
  process.env.TESTING_WORMHOLE_GUARDIAN_SET_INDEX!
);

// CircleIntegration
export const CIRCLE_INTEGRATION_ADDRESS =
  "0x955BfC83c95abB5B903AD82ECD32BB2aEb7DB138";

// signer
export const GUARDIAN_PRIVATE_KEY = process.env.TESTING_DEVNET_GUARDIAN!;
export const WALLET_PRIVATE_KEY = process.env.WALLET_PRIVATE_KEY!;

// mock guardian
export const GUARDIAN_SET_INDEX = 0;

// Ethereum Goerli Testnet
export const ETH_USDC_TOKEN_ADDRESS =
  process.env.TESTING_ETH_USDC_TOKEN_ADDRESS!;

// Avalanche Fuji Testnet
export const AVAX_USDC_TOKEN_ADDRESS =
  process.env.TESTING_AVAX_USDC_TOKEN_ADDRESS!;
