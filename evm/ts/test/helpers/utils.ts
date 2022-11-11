import { ethSignWithPrivate } from "@certusone/wormhole-sdk/lib/cjs/mock";
import { ethers } from "ethers";

export function getTimeNow() {
  return Math.floor(Date.now() / 1000);
}

export async function getBlockTimestamp(provider: ethers.providers.Provider) {
  return provider
    .getBlockNumber()
    .then((blockNumber) => provider.getBlock(blockNumber))
    .then((block) => block.timestamp);
}

// export function attestMessage(hash: ) {
//     const signature = ethSignWithPrivate(signer.key, hash);

//     const start = sigStart + i * SIGNATURE_PAYLOAD_LEN;
//     signedVaa.writeUInt8(signer.index, start);
//     signedVaa.write(
//       signature.r.toString(16).padStart(64, "0"),
//       start + 1,
//       "hex"
//     );
//     signedVaa.write(
//       signature.s.toString(16).padStart(64, "0"),
//       start + 33,
//       "hex"
//     );
//     signedVaa.writeUInt8(signature.recoveryParam!, start + 65);
// }
