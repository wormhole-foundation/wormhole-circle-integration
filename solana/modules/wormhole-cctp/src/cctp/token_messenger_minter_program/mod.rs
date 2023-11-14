#[cfg(feature = "cpi")]
pub mod cpi;

mod state;
pub use state::*;

cfg_if::cfg_if! {
    if #[cfg(feature = "mainnet")] {
        // Placeholder for real address
        anchor_lang::declare_id!("CCTPiPYPc6AsJuwueEnWgSgucamXDZwBd53dQ11YiKX3");
    } else if #[cfg(feature = "testnet")] {
        anchor_lang::declare_id!("CCTPiPYPc6AsJuwueEnWgSgucamXDZwBd53dQ11YiKX3");
    }
}

pub struct TokenMessengerMinter {}

impl anchor_lang::Id for TokenMessengerMinter {
    fn id() -> solana_program::pubkey::Pubkey {
        ID
    }
}
