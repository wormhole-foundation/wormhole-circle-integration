#![doc = include_str!("../README.md")]
#![allow(clippy::result_large_err)]

use anchor_lang::prelude::*;

cfg_if::cfg_if! {
    if #[cfg(feature = "mainnet")] {
        // Placeholder for real address
        declare_id!("Wormho1eCirc1e1ntegration111111111111111111");
    } else if #[cfg(feature = "testnet")] {
        declare_id!("wcihrWf1s91vfukW7LW8ZvR1rzpeZ9BrtZ8oyPkWK5d");
    }
}

pub mod constants;

pub mod error;

mod processor;
pub(crate) use processor::*;
pub use processor::{RedeemTokensWithPayloadArgs, TransferTokensWithPayloadArgs};

pub mod state;

#[program]
pub mod wormhole_circle_integration_solana {
    use super::*;

    pub fn initialize(ctx: Context<Initialize>) -> Result<()> {
        processor::initialize(ctx)
    }

    pub fn transfer_tokens_with_payload(
        ctx: Context<TransferTokensWithPayload>,
        args: TransferTokensWithPayloadArgs,
    ) -> Result<()> {
        processor::transfer_tokens_with_payload(ctx, args)
    }

    pub fn redeem_tokens_with_payload(
        ctx: Context<RedeemTokensWithPayload>,
        args: RedeemTokensWithPayloadArgs,
    ) -> Result<()> {
        processor::redeem_tokens_with_payload(ctx, args)
    }

    //  Governance

    pub fn register_emitter_and_domain(ctx: Context<RegisterEmitterAndDomain>) -> Result<()> {
        processor::register_emitter_and_domain(ctx)
    }

    pub fn upgrade_contract(ctx: Context<UpgradeContract>) -> Result<()> {
        processor::upgrade_contract(ctx)
    }
}
