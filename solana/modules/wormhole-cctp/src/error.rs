//! Errors for the Wormhole CCTP module.
//!
//! NOTE: These error values span from 0xffff0000 to 0xffff00ff so as to not collide with an
//! integrator's errors in his program.

#[anchor_lang::error_code(offset = 0)]
pub enum WormholeCctpError {
    #[msg("Cannot parse VAA payload as Wormhole CCTP message")]
    CannotParseMessage = 0xffff0001,

    #[msg("Cannot parse encoded CCTP message")]
    InvalidCctpMessage = 0xffff0002,

    #[msg("Not a Wormhole CCTP deposit message")]
    InvalidDepositMessage = 0xffff0003,

    #[msg("Source CCTP domain mismatch")]
    SourceCctpDomainMismatch = 0xffff0010,

    #[msg("Destination CCTP domain mismatch")]
    DestinationCctpDomainMismatch = 0xffff0011,

    #[msg("CCTP nonce mismatch")]
    CctpNonceMismatch = 0xffff0012,

    #[msg("Encoded mint recipient does not match mint recipient token account")]
    InvalidMintRecipient = 0xffff0014,
}
