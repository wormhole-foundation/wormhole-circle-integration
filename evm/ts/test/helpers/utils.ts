import { tryNativeToHexString } from "@certusone/wormhole-sdk";
import { ethSignWithPrivate } from "@certusone/wormhole-sdk/lib/cjs/mock";
import { ethers } from "ethers";
import * as fs from "fs";

export function getTimeNow() {
  return Math.floor(Date.now() / 1000);
}

export function readCircleIntegrationProxyAddress(chain: number): string {
  return JSON.parse(
    fs.readFileSync(
      `${__dirname}/../../../broadcast-test/deploy_contracts.sol/${chain}/run-latest.json`,
      "utf-8"
    )
  ).transactions[2].contractAddress;
}

export function findWormholeMessageInLogs(
  logs: ethers.providers.Log[],
  wormholeAddress: string,
  emitterChain: number
) {
  for (const log of logs) {
    if (log.address == wormholeAddress) {
      const iface = new ethers.utils.Interface([
        "event LogMessagePublished(address indexed sender, uint64 sequence, uint32 nonce, bytes payload, uint8 consistencyLevel)",
      ]);

      const result = iface.parseLog(log).args;
      const payload = ethers.utils.arrayify(result.payload);

      const message = Buffer.alloc(51 + payload.length);

      message.writeUInt32BE(getTimeNow(), 0);
      message.writeUInt32BE(Number(result.nonce), 4);
      message.writeUInt16BE(emitterChain, 8);
      message.write(
        tryNativeToHexString(result.sender.toString(), "ethereum"),
        10,
        "hex"
      );
      message.writeBigUInt64BE(BigInt(result.sequence.toString()), 42);
      message.writeUInt8(Number(result.consistencyLevel), 50);
      message.write(Buffer.from(payload).toString("hex"), 51, "hex");

      return message;
    }
  }

  return null;
}

export class MockCircleAttester {
  privateKey: string;

  constructor(privateKey: string) {
    this.privateKey = privateKey;
  }

  attestMessage(message: Uint8Array): Uint8Array {
    const signature = ethSignWithPrivate(
      this.privateKey,
      Buffer.from(ethers.utils.arrayify(ethers.utils.keccak256(message)))
    );
    const out = Buffer.alloc(65);

    out.write(signature.r.toString(16).padStart(64, "0"), 0, "hex");
    out.write(signature.s.toString(16).padStart(64, "0"), 32, "hex");
    out.writeUInt8(signature.recoveryParam! + 27, 64);
    return Uint8Array.from(out);
  }
}
