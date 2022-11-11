import { ethers } from "ethers";

// ethereum goerli testnet fork
export const ETH_LOCALHOST = "http://localhost:8545";
export const ETH_FORK_CHAIN_ID = Number(process.env.ETH_FORK_CHAIN_ID!);
export const ETH_WORMHOLE_ADDRESS = process.env.ETH_WORMHOLE_ADDRESS!;
export const ETH_USDC_TOKEN_ADDRESS = process.env.ETH_USDC_TOKEN_ADDRESS!;
export const ETH_CIRCLE_BRIDGE_ADDRESS = process.env.ETH_CIRCLE_BRIDGE_ADDRESS!;

// avalanche fuji testnet fork
export const AVAX_LOCALHOST = "http://localhost:8546";
export const AVAX_FORK_CHAIN_ID = Number(process.env.AVAX_FORK_CHAIN_ID!);
export const AVAX_WORMHOLE_ADDRESS = process.env.AVAX_WORMHOLE_ADDRESS!;
export const AVAX_USDC_TOKEN_ADDRESS = process.env.AVAX_USDC_TOKEN_ADDRESS!;
export const AVAX_CIRCLE_BRIDGE_ADDRESS =
  process.env.AVAX_CIRCLE_BRIDGE_ADDRESS!;

// global
export const WORMHOLE_MESSAGE_FEE = ethers.BigNumber.from(
  process.env.TESTING_WORMHOLE_MESSAGE_FEE!
);
export const WORMHOLE_GUARDIAN_SET_INDEX = Number(
  process.env.TESTING_WORMHOLE_GUARDIAN_SET_INDEX!
);
export const GUARDIAN_PRIVATE_KEY = process.env.TESTING_DEVNET_GUARDIAN!;
export const WALLET_PRIVATE_KEY = process.env.WALLET_PRIVATE_KEY!;
