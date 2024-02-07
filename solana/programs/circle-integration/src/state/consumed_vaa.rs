use anchor_lang::prelude::*;

#[account]
#[derive(Debug, InitSpace)]
pub struct ConsumedVaa {
    pub bump: u8,
}

impl ConsumedVaa {
    pub const SEED_PREFIX: &'static [u8] = b"consumed-vaa";
}
