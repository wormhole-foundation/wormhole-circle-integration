use anchor_lang::prelude::*;

#[derive(Debug, AnchorSerialize, AnchorDeserialize, Clone)]
pub struct RemoteTokenMessenger {
    pub domain: u32,
    pub token_messenger: [u8; 32],
}

impl RemoteTokenMessenger {
    pub const SEED_PREFIX: &'static [u8] = b"remote_token_messenger";
}

impl anchor_lang::Discriminator for RemoteTokenMessenger {
    const DISCRIMINATOR: [u8; 8] = [105, 115, 174, 34, 95, 233, 138, 252];
}

impl Owner for RemoteTokenMessenger {
    fn owner() -> Pubkey {
        crate::cctp::token_messenger_minter_program::ID
    }
}
