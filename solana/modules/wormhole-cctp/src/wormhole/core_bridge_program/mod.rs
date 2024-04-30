#[cfg(feature = "cpi")]
pub mod cpi;

pub mod state;

use anchor_lang::prelude::*;

declare_id!(wormhole_solana_consts::CORE_BRIDGE_PROGRAM_ID);

/// Representation of Solana's commitment levels. This enum is not exhaustive because Wormhole only
/// considers these two commitment levels in its Guardian observation.
///
/// See <https://docs.solana.com/cluster/commitments> for more info.
#[derive(Copy, Debug, AnchorSerialize, AnchorDeserialize, Clone, PartialEq, Eq)]
pub enum Commitment {
    /// One confirmation.
    Confirmed,
    /// 32 confirmations.
    Finalized,
}
