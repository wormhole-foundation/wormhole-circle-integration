import { ethers } from "ethers";

export interface DepositWithPayload {
  token: Buffer;
  amount: ethers.BigNumber;
  sourceDomain: number;
  targetDomain: number;
  nonce: number;
  fromAddress: Buffer;
  mintRecipient: Buffer;
  payload: Buffer;
}
