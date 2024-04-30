#[cfg(feature = "cpi")]
pub mod cpi;

mod state;
pub use state::*;

anchor_lang::declare_id!(crate::cctp::TOKEN_MESSENGER_MINTER_PROGRAM_ID);
