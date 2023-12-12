import {GovernanceEmitter} from "@certusone/wormhole-sdk/lib/esm/mock";
import {ethers} from "ethers";

export interface Transfer {
  token: string;
  amount: ethers.BigNumber;
  targetChain: number;
  mintRecipient: Buffer;
}

export interface MockDepositWithPayload {
  nonce: number;
  fromAddress: Buffer;
}

export class CircleGovernanceEmitter extends GovernanceEmitter {
  constructor(startSequence?: number) {
    super(
      "0000000000000000000000000000000000000000000000000000000000000004",
      startSequence
    );
  }

  publishCircleIntegrationUpdateFinality(
    timestamp: number,
    chain: number,
    finality: number,
    uptickSequence: boolean = true
  ) {
    const payload = Buffer.alloc(1);
    payload.writeUIntBE(finality, 0, 1);
    return this.publishGovernanceMessage(
      timestamp,
      "CircleIntegration",
      payload,
      1,
      chain,
      uptickSequence
    );
  }

  publishCircleIntegrationRegisterEmitterAndDomain(
    timestamp: number,
    chain: number,
    emitterChain: number,
    emitterAddress: Buffer,
    domain: number,
    uptickSequence: boolean = true
  ) {
    const payload = Buffer.alloc(38);
    payload.writeUInt16BE(emitterChain, 0);
    payload.write(emitterAddress.toString("hex"), 2, "hex");
    payload.writeUInt32BE(domain, 34);
    return this.publishGovernanceMessage(
      timestamp,
      "CircleIntegration",
      payload,
      2,
      chain,
      uptickSequence
    );
  }

  publishCircleIntegrationUpgradeContract(
    timestamp: number,
    chain: number,
    newImplementation: Uint8Array,
    uptickSequence: boolean = true
  ) {
    const payload = Buffer.alloc(32, Buffer.from(newImplementation));
    return this.publishGovernanceMessage(
      timestamp,
      "CircleIntegration",
      payload,
      3,
      chain,
      uptickSequence
    );
  }
}
