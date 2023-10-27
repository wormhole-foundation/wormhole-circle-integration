import { ethers } from "ethers";
import yargs from "yargs";
import type { Argv } from "yargs";
import { hideBin } from "yargs/helpers";

export type SignerArguments =
  | {
      useLedger: true;
      derivationPath: string;
    }
  | {
      useLedger: false;
      privateKey: string;
    };

/**
 * @dev Use this to enrich your argument parsing with signer options
 */
export function addSignerArgsParser<T>(parser: Argv<T>) {
  return parser
    .option("ledger", {
      boolean: true,
      default: false,
      description: "Use ledger to sign transactions",
      required: false,
    })
    .option("derivation-path", {
      string: true,
      description:
        "BIP32 derivation path to use. Used only with ledger devices.",
      required: false,
    })
    .option("private-key", {
      string: true,
      description: "EVM Private Key.",
      required: false,
    });
}

type ParsedSignerArgs = Awaited<
  ReturnType<ReturnType<typeof addSignerArgsParser>["parse"]>
>;

/**
 * @notice Use this if you don't parse any arguments and need to provide
 * signer options.
 */
export async function parseSignerArgs() {
  const signerArgsParser = addSignerArgsParser(yargs())
    .help("h")
    .alias("h", "help");
  const args = await signerArgsParser.parse(hideBin(process.argv));
  return validateSignerArgs(args);
}

export function validateSignerArgs(
  args: ParsedSignerArgs,
): SignerArguments {
  if ((args.privateKey !== undefined) === args.ledger) {
    throw new Error(
      "Exactly one signing method must be provided. Use either the '--ledger' or the '--privateKey' options.",
    );
  }

  if (args.ledger) {
    if (args.derivationPath === undefined) {
      throw new Error(
        "An account must be selected using the '--derivation-path' option when signing with a ledger device.",
      );
    }

    return {
      useLedger: true,
      derivationPath: args.derivationPath,
    };
  }

  return {
    useLedger: false,
    // The private key cannot be undefined at this point but typescript's type narrowing is a bit lacking to determine that.
    privateKey: args.privateKey!,
  };
}

export async function getSigner(
  args: SignerArguments,
  provider: ethers.providers.Provider,
): Promise<ethers.Signer> {
  if (args.useLedger) {
    const { LedgerSigner } = await import("@xlabs-xyz/ledger-signer");
    return LedgerSigner.create(provider, args.derivationPath);
  }

  return new ethers.Wallet(args.privateKey, provider);
}
