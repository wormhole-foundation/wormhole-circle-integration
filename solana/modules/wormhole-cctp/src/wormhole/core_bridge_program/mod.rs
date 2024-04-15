#[cfg(feature = "cpi")]
pub mod cpi;

pub mod state;

use anchor_lang::prelude::*;

pub const SOLANA_CHAIN: u16 = 1;

cfg_if::cfg_if! {
    if #[cfg(feature = "localnet")] {
        declare_id!("Bridge1p5gheXUvJ6jGWGeCsgPKgnE3YgdGKRVCMY9o");
    } else if #[cfg(feature = "mainnet")] {
        declare_id!("worm2ZoG2kUd4vFXhvjh93UUH596ayRfgQ2MgjNMTth");
    } else if #[cfg(feature = "testnet")] {
        declare_id!("3u8hJUVTA4jH1wYAyUur7FFZVQ8H635K3tSHHF4ssjQ5");
    }
}

pub struct CoreBridge;

impl Id for CoreBridge {
    fn id() -> Pubkey {
        ID
    }
}

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
