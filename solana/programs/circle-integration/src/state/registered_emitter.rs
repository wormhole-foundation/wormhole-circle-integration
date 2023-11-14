use anchor_lang::prelude::*;

#[account]
#[derive(Debug, InitSpace)]
pub struct RegisteredEmitter {
    pub bump: u8,
    pub cctp_domain: u32,
    pub chain: u16,
    pub address: [u8; 32],
}

impl RegisteredEmitter {
    pub const SEED_PREFIX: &'static [u8] = b"registered_emitter";
}
