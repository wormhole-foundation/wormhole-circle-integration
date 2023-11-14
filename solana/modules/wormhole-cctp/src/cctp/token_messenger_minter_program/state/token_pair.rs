use anchor_lang::prelude::*;

#[derive(Debug, AnchorSerialize, AnchorDeserialize, Clone)]
pub struct TokenPair {
    pub remote_domain: u32,
    pub remote_token_address: [u8; 32],
    pub local_token: Pubkey,
    pub bump: u8,
}

impl TokenPair {
    pub const SEED_PREFIX: &'static [u8] = b"token_pair";
}

impl anchor_lang::Discriminator for TokenPair {
    const DISCRIMINATOR: [u8; 8] = [17, 214, 45, 176, 229, 149, 197, 71];
}

impl Owner for TokenPair {
    fn owner() -> Pubkey {
        crate::cctp::token_messenger_minter_program::ID
    }
}
