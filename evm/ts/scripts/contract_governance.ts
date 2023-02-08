import {ethers} from "ethers";
import {
  CHAIN_ID_ALGORAND,
  CHAIN_ID_AVAX,
  CHAIN_ID_ETH,
  tryNativeToUint8Array,
  ChainId,
} from "@certusone/wormhole-sdk";
import {MockGuardians} from "@certusone/wormhole-sdk/lib/cjs/mock";
import {CircleGovernanceEmitter} from "../test/helpers/mock";
import {abi as WORMHOLE_ABI} from "../../out/IWormhole.sol/IWormhole.json";
import {abi as CIRCLE_INTEGRATION_ABI} from "../../out/CircleIntegration.sol/CircleIntegration.json";
import {getTimeNow} from "../test/helpers/utils";
import {expect} from "chai";

require("dotenv").config({path: process.argv.slice(2)[0]});

// ethereum wallet, CircleIntegration contract and USDC contract
const provider = new ethers.providers.StaticJsonRpcProvider(
  process.env.SOURCE_PROVIDER!
);
const wallet = new ethers.Wallet(process.env.WALLET_PRIVATE_KEY!, provider);

// set up Wormhole instance
let wormhole = new ethers.Contract(
  process.env.SOURCE_WORMHOLE!,
  WORMHOLE_ABI,
  provider
);
wormhole = wormhole.connect(wallet);

// set up circleIntegration contract
let circleIntegration = new ethers.Contract(
  process.env.SOURCE_CIRCLE_INTEGRATION_ADDRESS!,
  CIRCLE_INTEGRATION_ABI,
  provider
);
circleIntegration = circleIntegration.connect(wallet);

// produces governance VAAs for CircleAttestation contract
const governance = new CircleGovernanceEmitter();

async function registerEmitterAndDomain() {
  // MockGuardians and MockCircleAttester objects
  const guardians = new MockGuardians(
    await wormhole.getCurrentGuardianSetIndex(),
    [process.env.TESTNET_GUARDIAN_KEY!]
  );

  // put together VAA
  const timestamp = getTimeNow();
  const chainId = Number(process.env.SOURCE_CHAIN_ID!);
  const emitterChain = Number(process.env.TARGET_CHAIN_ID!);
  const emitterAddress = Buffer.from(
    tryNativeToUint8Array(
      process.env.TARGET_CIRCLE_INTEGRATION_ADDRESS!,
      "avalanche"
    )
  );
  const domain = Number(process.env.TARGET_DOMAIN!);

  // create unsigned registerEmitterAndDomain governance message
  const published = governance.publishCircleIntegrationRegisterEmitterAndDomain(
    timestamp,
    chainId,
    emitterChain,
    emitterAddress,
    domain
  );

  // sign the governance VAA with the testnet guardian key
  const signedMessage = guardians.addSignatures(published, [0]);

  // register the emitter and domain
  const receipt = await circleIntegration
    .registerEmitterAndDomain(signedMessage)
    .then((tx: ethers.ContractTransaction) => tx.wait())
    .catch((msg: string) => {
      // should not happen
      console.log(msg);
      return null;
    });

  // check contract state to verify the registration
  const registeredEmitter = await circleIntegration
    .getRegisteredEmitter(emitterChain)
    .then((bytes: ethers.BytesLike) =>
      Buffer.from(ethers.utils.arrayify(bytes))
    );
  expect(Buffer.compare(registeredEmitter, emitterAddress)).to.equal(0);
}

async function updateFinality() {
  // MockGuardians and MockCircleAttester objects
  const guardians = new MockGuardians(
    await wormhole.getCurrentGuardianSetIndex(),
    [process.env.TESTNET_GUARDIAN_KEY!]
  );

  const timestamp = getTimeNow();
  const chainId = Number(process.env.SOURCE_CHAIN_ID!);
  const finality = Number(process.env.SOURCE_FINALITY!);

  // create unsigned registerTargetChainToken governance message
  const published = governance.publishCircleIntegrationUpdateFinality(
    timestamp,
    chainId,
    finality
  );

  // sign governance message with guardian key
  const signedMessage = guardians.addSignatures(published, [0]);

  // register the target token
  const receipt = await circleIntegration
    .updateWormholeFinality(signedMessage)
    .then((tx: ethers.ContractTransaction) => tx.wait())
    .catch((msg: string) => {
      // should not happen
      console.log(msg);
      return null;
    });
  expect(receipt).is.not.null;
}

updateFinality();
