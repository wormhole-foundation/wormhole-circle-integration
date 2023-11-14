use crate::{constants::UPGRADE_SEED_PREFIX, error::CircleIntegrationError, state::Custodian};
use anchor_lang::prelude::*;
use solana_program::bpf_loader_upgradeable;
use wormhole_cctp_solana::wormhole::core_bridge_program;

#[derive(Accounts)]
pub struct UpgradeContract<'info> {
    #[account(mut)]
    payer: Signer<'info>,

    #[account(
        seeds = [Custodian::SEED_PREFIX],
        bump = custodian.bump,
    )]
    custodian: Account<'info, Custodian>,

    /// CHECK: Posted VAA account, which will be read via zero-copy deserialization in the
    /// instruction handler, which also checks this account discriminator (so there is no need to
    /// check PDA seeds here).
    #[account(
        mut,
        owner = core_bridge_program::id()
    )]
    vaa: AccountInfo<'info>,

    /// CHECK: Account representing that a VAA has been consumed. Seeds are checked when
    /// [claim_vaa](core_bridge_sdk::claim_vaa) is called.
    #[account(mut)]
    claim: AccountInfo<'info>,

    /// CHECK: We need this upgrade authority to invoke the BPF Loader Upgradeable program to
    /// upgrade this program's executable. We verify this PDA address here out of convenience to get
    /// the PDA bump seed to invoke the upgrade.
    #[account(
        seeds = [UPGRADE_SEED_PREFIX],
        bump = custodian.upgrade_authority_bump,
    )]
    upgrade_authority: AccountInfo<'info>,

    /// CHECK: This account receives any lamports after the result of the upgrade.
    #[account(mut)]
    spill: AccountInfo<'info>,

    /// CHECK: Deployed implementation. The pubkey of this account is checked in access control
    /// against the one encoded in the governance VAA.
    #[account(mut)]
    buffer: AccountInfo<'info>,

    /// CHECK: Token Bridge program data needed for BPF Loader Upgradable program.
    #[account(
        mut,
        seeds = [crate::ID.as_ref()],
        bump,
        seeds::program = bpf_loader_upgradeable::id(),
    )]
    program_data: AccountInfo<'info>,

    /// CHECK: This must equal the Token Bridge program ID for the BPF Loader Upgradeable program.
    #[account(
        mut,
        address = crate::ID
    )]
    this_program: AccountInfo<'info>,

    /// CHECK: BPF Loader Upgradeable program needs this sysvar.
    #[account(address = solana_program::sysvar::rent::id())]
    rent: AccountInfo<'info>,

    /// CHECK: BPF Loader Upgradeable program needs this sysvar.
    #[account(address = solana_program::sysvar::clock::id())]
    clock: AccountInfo<'info>,

    /// CHECK: BPF Loader Upgradeable program.
    #[account(address = bpf_loader_upgradeable::id())]
    bpf_loader_upgradeable_program: AccountInfo<'info>,

    system_program: Program<'info, System>,
}

/// Processor for contract upgrade governance decrees. This instruction handler invokes the BPF
/// Loader Upgradeable program to upgrade this program's executable to the provided buffer.
#[access_control(handle_access_control(&ctx))]
pub fn upgrade_contract(ctx: Context<UpgradeContract>) -> Result<()> {
    let vaa = core_bridge_program::VaaAccount::load(&ctx.accounts.vaa).unwrap();

    // Create the claim account to provide replay protection. Because this instruction creates this
    // account every time it is executed, this account cannot be created again with this emitter
    // address, chain and sequence combination.
    core_bridge_program::sdk::claim_vaa(
        CpiContext::new(
            ctx.accounts.system_program.to_account_info(),
            core_bridge_program::sdk::ClaimVaa {
                claim: ctx.accounts.claim.to_account_info(),
                payer: ctx.accounts.payer.to_account_info(),
            },
        ),
        &crate::ID,
        &vaa,
        None,
    )?;

    // Finally upgrade.
    solana_program::program::invoke_signed(
        &bpf_loader_upgradeable::upgrade(
            &crate::ID,
            &ctx.accounts.buffer.key(),
            &ctx.accounts.upgrade_authority.key(),
            &ctx.accounts.spill.key(),
        ),
        &ctx.accounts.to_account_infos(),
        &[&[
            UPGRADE_SEED_PREFIX,
            &[ctx.accounts.custodian.upgrade_authority_bump],
        ]],
    )
    .map_err(Into::into)
}

fn handle_access_control(ctx: &Context<UpgradeContract>) -> Result<()> {
    let vaa = core_bridge_program::VaaAccount::load(&ctx.accounts.vaa)?;
    let gov_payload = crate::processor::require_valid_governance_vaa(&vaa)?;

    let upgrade = gov_payload
        .contract_upgrade()
        .ok_or(error!(CircleIntegrationError::InvalidGovernanceAction))?;

    // Make sure that the contract upgrade is intended for this network.
    require_eq!(
        upgrade.chain(),
        core_bridge_program::SOLANA_CHAIN,
        CircleIntegrationError::GovernanceForAnotherChain
    );

    // Read the implementation pubkey and check against the buffer in our account context.
    require_keys_eq!(
        Pubkey::from(upgrade.implementation()),
        ctx.accounts.buffer.key(),
        CircleIntegrationError::ImplementationMismatch
    );

    // Done.
    Ok(())
}
