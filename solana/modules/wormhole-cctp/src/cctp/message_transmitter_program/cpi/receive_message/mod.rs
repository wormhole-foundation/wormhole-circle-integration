mod token_messenger_minter;
pub use token_messenger_minter::*;

use anchor_lang::prelude::*;

/// Common arguments to redeem messages via the CCTP Message Transmitter program using its receive
/// message instruction.
#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct ReceiveMessageArgs {
    /// CCTP message.
    pub encoded_message: Vec<u8>,

    /// Attestation of [encoded_message](Self::encoded_message).
    pub attestation: Vec<u8>,
}
