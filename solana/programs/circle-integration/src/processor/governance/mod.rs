mod register_emitter_and_domain;
pub use register_emitter_and_domain::*;

mod upgrade_contract;
pub use upgrade_contract::*;

use crate::error::CircleIntegrationError;
use anchor_lang::prelude::*;
use wormhole_cctp_solana::wormhole::core_bridge_program;
use wormhole_raw_vaas::cctp::{CircleIntegrationDecree, CircleIntegrationGovPayload};

pub fn require_valid_governance_vaa<'ctx>(
    vaa: &'ctx core_bridge_program::VaaAccount<'ctx>,
) -> Result<CircleIntegrationDecree<'ctx>> {
    let emitter = vaa.try_emitter_info()?;
    require!(
        emitter.chain == crate::constants::GOVERNANCE_CHAIN
            && emitter.address == crate::constants::GOVERNANCE_EMITTER,
        CircleIntegrationError::InvalidGovernanceEmitter
    );

    // Because emitter_chain and emitter_address getters have succeeded, we can safely unwrap this
    // payload call.
    CircleIntegrationGovPayload::try_from(vaa.try_payload().unwrap())
        .map(|msg| msg.decree())
        .map_err(|_| error!(CircleIntegrationError::InvalidGovernanceVaa))
}
