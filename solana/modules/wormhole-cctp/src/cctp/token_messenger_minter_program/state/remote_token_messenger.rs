use anchor_lang::prelude::*;

#[derive(Debug, AnchorSerialize, AnchorDeserialize, Clone)]
pub struct RemoteTokenMessenger {
    pub domain: u32,
    pub token_messenger: [u8; 32],
}

impl RemoteTokenMessenger {
    pub const SEED_PREFIX: &'static [u8] = b"remote_token_messenger";
}

wormhole_solana_utils::impl_anchor_account_readonly!(
    RemoteTokenMessenger,
    crate::cctp::TOKEN_MESSENGER_MINTER_PROGRAM_ID,
    [105, 115, 174, 34, 95, 233, 138, 252]
);
