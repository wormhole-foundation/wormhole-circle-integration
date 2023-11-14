#[cfg(feature = "cpi")]
pub mod cpi;

mod state;
pub use state::*;

cfg_if::cfg_if! {
    if #[cfg(feature = "mainnet")] {
        // Placeholder for real address
        anchor_lang::declare_id!("CCTPmbSD7gX1bxKPAmg77w8oFzNFpaQiQUWD43TKaecd");
    } else if #[cfg(feature = "testnet")] {
        anchor_lang::declare_id!("CCTPmbSD7gX1bxKPAmg77w8oFzNFpaQiQUWD43TKaecd");
    }
}

pub struct MessageTransmitter {}

impl anchor_lang::Id for MessageTransmitter {
    fn id() -> solana_program::pubkey::Pubkey {
        ID
    }
}
