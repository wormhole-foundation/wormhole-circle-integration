pub mod message_transmitter_program;

pub mod token_messenger_minter_program;

use solana_program::{pubkey, pubkey::Pubkey};

pub const MESSAGE_TRANSMITTER_PROGRAM_ID: Pubkey =
    pubkey!("CCTPmbSD7gX1bxKPAmg77w8oFzNFpaQiQUWD43TKaecd");
pub const TOKEN_MESSENGER_MINTER_PROGRAM_ID: Pubkey =
    pubkey!("CCTPiPYPc6AsJuwueEnWgSgucamXDZwBd53dQ11YiKX3");
