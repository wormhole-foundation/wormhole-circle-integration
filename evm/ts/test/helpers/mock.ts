import { coalesceChainId, tryNativeToHexString } from "@certusone/wormhole-sdk";
import {
  GovernanceEmitter,
  MockEmitter,
} from "@certusone/wormhole-sdk/lib/cjs/mock";
import { ethers } from "ethers";
import { DepositWithPayload, ICircleIntegration } from "../../src";

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

export class MockCircleIntegration extends MockEmitter {
  domain: number;
  foreignCircleIntegration: ICircleIntegration;

  constructor(
    address: string,
    chain: number,
    domain: number,
    foreignCircleIntegration: ICircleIntegration
  ) {
    super(tryNativeToHexString(address, "ethereum"), chain);
    this.domain = domain;
    this.foreignCircleIntegration = foreignCircleIntegration;
  }

  async transferTokensWithPayload() {
    // mockParams: MockDepositWithPayload // payload: Buffer, // batchId: number, // transfer: Transfer,
    const foreign = this.foreignCircleIntegration;

    const targetDomain = await foreign.localDomain();

    // const depositWithPayload: DepositWithPayload = {
    // }
    // const encoded =
    //   await this.interfaceContract.encodeWormholeDepositWithPayload({});
  }
}

export class CircleGovernanceEmitter extends GovernanceEmitter {
  constructor(startSequence?: number) {
    super(
      "0000000000000000000000000000000000000000000000000000000000000004",
      startSequence
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

  publishCircleIntegrationRegisterAcceptedToken(
    timestamp: number,
    chain: number,
    tokenAddress: string,
    uptickSequence: boolean = true
  ) {
    const payload = Buffer.alloc(32);
    payload.write(tryNativeToHexString(tokenAddress, "ethereum"), 0, "hex");
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
