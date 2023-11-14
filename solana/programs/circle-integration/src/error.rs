//! Errors that may arise when interacting with the Wormhole Circle Integration Program.
//!

#[anchor_lang::prelude::error_code]
pub enum CircleIntegrationError {
    #[msg("InvalidGovernanceEmitter")]
    InvalidGovernanceEmitter = 0x2,

    #[msg("InvalidGovernanceVaa")]
    InvalidGovernanceVaa = 0x4,

    #[msg("InvalidGovernanceAction")]
    InvalidGovernanceAction = 0x6,

    #[msg("GovernanceForAnotherChain")]
    GovernanceForAnotherChain = 0x8,

    #[msg("ImplementationMismatch")]
    ImplementationMismatch = 0x20,

    #[msg("InvalidForeignChain")]
    InvalidForeignChain = 0x40,

    #[msg("InvalidForeignEmitter")]
    InvalidForeignEmitter = 0x42,

    #[msg("InvalidCctpDomain")]
    InvalidCctpDomain = 0x44,

    #[msg("UnknownEmitter")]
    UnknownEmitter = 0x102,
}
