use anchor_lang::prelude::*;

/// Emitter config account. This account is used to perform the following:
/// 1. It is the emitter authority for the Core Bridge program.
/// 2. It acts as the custody token account owner for token transfers.
#[account]
#[derive(Debug, InitSpace)]
pub struct Custodian {
    pub bump: u8,
    pub upgrade_authority_bump: u8,
}

impl Custodian {
    pub const SEED_PREFIX: &'static [u8] = b"emitter";
}
