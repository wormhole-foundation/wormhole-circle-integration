#[cfg(feature = "cpi")]
pub mod cpi;

mod state;
pub use state::*;

anchor_lang::declare_id!(crate::cctp::MESSAGE_TRANSMITTER_PROGRAM_ID);
