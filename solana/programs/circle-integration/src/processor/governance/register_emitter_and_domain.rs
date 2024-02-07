use crate::{
    error::CircleIntegrationError,
    state::{ConsumedVaa, Custodian, RegisteredEmitter},
};
use anchor_lang::prelude::*;
use wormhole_cctp_solana::{
    cctp::token_messenger_minter_program,
    utils::ExternalAccount,
    wormhole::core_bridge_program::{self, VaaAccount},
};
use wormhole_raw_vaas::cctp::CircleIntegrationGovPayload;

#[derive(Accounts)]
pub struct RegisterEmitterAndDomain<'info> {
    #[account(mut)]
    payer: Signer<'info>,

    #[account(
        seeds = [Custodian::SEED_PREFIX],
        bump = custodian.bump,
    )]
    custodian: Account<'info, Custodian>,

    /// CHECK: We will be performing zero-copy deserialization in the instruction handler.
    #[account(owner = core_bridge_program::id())]
    vaa: AccountInfo<'info>,

    #[account(
        init,
        payer = payer,
        space = 8 + RegisteredEmitter::INIT_SPACE,
        seeds = [
            RegisteredEmitter::SEED_PREFIX,
            try_decree(&vaa, |decree| decree.foreign_chain())?.to_be_bytes().as_ref(),
        ],
        bump,
    )]
    registered_emitter: Account<'info, RegisteredEmitter>,

    #[account(
        init,
        payer = payer,
        space = 8 + ConsumedVaa::INIT_SPACE,
        seeds = [
            ConsumedVaa::SEED_PREFIX,
            VaaAccount::load(&vaa)?.try_digest()?.as_ref(),
        ],
        bump,
    )]
    consumed_vaa: Account<'info, ConsumedVaa>,

    #[account(
        seeds = [
            token_messenger_minter_program::RemoteTokenMessenger::SEED_PREFIX,
            try_decree(&vaa, |decree| decree.cctp_domain())?.to_string().as_ref(),
        ],
        bump,
        seeds::program = token_messenger_minter_program::id(),
    )]
    remote_token_messenger:
        Account<'info, ExternalAccount<token_messenger_minter_program::RemoteTokenMessenger>>,

    system_program: Program<'info, System>,
}

#[access_control(handle_access_control(&ctx))]
pub fn register_emitter_and_domain(ctx: Context<RegisterEmitterAndDomain>) -> Result<()> {
    ctx.accounts.consumed_vaa.set_inner(ConsumedVaa {
        bump: ctx.bumps.consumed_vaa,
    });

    let vaa = core_bridge_program::VaaAccount::load(&ctx.accounts.vaa).unwrap();

    let registration = CircleIntegrationGovPayload::try_from(vaa.try_payload().unwrap())
        .unwrap()
        .decree()
        .to_register_emitter_and_domain_unchecked();

    ctx.accounts
        .registered_emitter
        .set_inner(RegisteredEmitter {
            bump: ctx.bumps.registered_emitter,
            cctp_domain: registration.cctp_domain(),
            chain: registration.foreign_chain(),
            address: registration.foreign_emitter(),
        });

    // Done.
    Ok(())
}

fn try_decree<F, T>(vaa_acc_info: &AccountInfo, func: F) -> Result<T>
where
    T: std::fmt::Debug,
    F: FnOnce(&wormhole_raw_vaas::cctp::RegisterEmitterAndDomain) -> T,
{
    let vaa = core_bridge_program::VaaAccount::load(vaa_acc_info)?;
    let payload = vaa.try_payload()?;

    let gov_payload = CircleIntegrationGovPayload::parse(payload.as_ref())
        .map_err(|_| error!(CircleIntegrationError::InvalidGovernanceVaa))?;
    gov_payload
        .decree()
        .register_emitter_and_domain()
        .map(func)
        .ok_or(error!(CircleIntegrationError::InvalidGovernanceAction))
}

fn handle_access_control(ctx: &Context<RegisterEmitterAndDomain>) -> Result<()> {
    let vaa = core_bridge_program::VaaAccount::load(&ctx.accounts.vaa)?;
    let gov_payload = crate::processor::require_valid_governance_vaa(&vaa)?;

    let registration = gov_payload
        .register_emitter_and_domain()
        .ok_or(error!(CircleIntegrationError::InvalidGovernanceAction))?;

    // Registration is either for this chain (Solana) or for all chains (encoded as zero).
    let decree_chain = registration.chain();
    require!(
        decree_chain == 0 || decree_chain == core_bridge_program::SOLANA_CHAIN,
        CircleIntegrationError::GovernanceForAnotherChain
    );

    // Foreign chain and emitter address cannot be zero or Solana's.
    let foreign_chain = registration.foreign_chain();
    require!(
        foreign_chain != 0 && foreign_chain != core_bridge_program::SOLANA_CHAIN,
        CircleIntegrationError::InvalidForeignChain
    );
    require!(
        registration.foreign_emitter() != [0; 32],
        CircleIntegrationError::InvalidForeignEmitter
    );

    // CCTP domain must equal the one in the Remote Token Messenger account.
    //
    // NOTE: This statement should always pass. But we keep this check just in case the owner
    // of the Token Messenger Minter program misconfigured the Remote Token Messenger account.
    require!(
        registration.cctp_domain() == ctx.accounts.remote_token_messenger.domain,
        CircleIntegrationError::InvalidCctpDomain
    );

    // Done.
    Ok(())
}
