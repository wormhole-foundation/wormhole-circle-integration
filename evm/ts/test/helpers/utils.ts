import { ethers } from "ethers";

export async function getBlockTimestamp(provider: ethers.providers.Provider) {
  return provider
    .getBlockNumber()
    .then((blockNumber) => provider.getBlock(blockNumber))
    .then((block) => block.timestamp);
}
