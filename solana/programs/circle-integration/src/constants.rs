//! Constants used by the Wormhole Circle Integration Program.

use anchor_lang::prelude::constant;

/// Seed for upgrade authority.
#[constant]
pub const UPGRADE_SEED_PREFIX: &[u8] = b"upgrade";

/// Seed for custody token account.
#[constant]
pub const CUSTODY_TOKEN_SEED_PREFIX: &[u8] = b"custody";

pub(crate) const GOVERNANCE_CHAIN: u16 = 1;

pub(crate) const GOVERNANCE_EMITTER: [u8; 32] = [
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4,
];
