use anchor_lang::prelude::*;

#[derive(Debug, AnchorSerialize, AnchorDeserialize, Clone)]
pub struct LocalToken {
    pub custody_token: Pubkey,
    pub mint: Pubkey,
    pub burn_limit_per_message: u64,
    pub messages_sent: u64,
    pub messages_received: u64,
    pub amount_sent: u128,
    pub amount_received: u128,
    pub bump: u8,
    pub custody_bump: u8,
}

impl LocalToken {
    pub const SEED_PREFIX: &'static [u8] = b"local_token";
}

wormhole_solana_utils::impl_anchor_account_readonly!(
    LocalToken,
    crate::cctp::TOKEN_MESSENGER_MINTER_PROGRAM_ID,
    [159, 131, 58, 170, 193, 84, 128, 182]
);
