use crate::{constants::UPGRADE_SEED_PREFIX, state::Custodian};
use anchor_lang::prelude::*;
use solana_program::bpf_loader_upgradeable;

#[derive(Accounts)]
pub struct Initialize<'info> {
    #[account(mut)]
    deployer: Signer<'info>,

    #[account(
        init,
        payer = deployer,
        space = 8 + Custodian::INIT_SPACE,
        seeds = [Custodian::SEED_PREFIX],
        bump,
    )]
    custodian: Account<'info, Custodian>,

    /// CHECK: We need this upgrade authority to invoke the BPF Loader Upgradeable program to
    /// upgrade this program's executable. We verify this PDA address here out of convenience to get
    /// the PDA bump seed to invoke the upgrade.
    #[account(
        seeds = [UPGRADE_SEED_PREFIX],
        bump,
    )]
    upgrade_authority: AccountInfo<'info>,

    /// CHECK: Wormhole Circle Integration program data needed for BPF Loader Upgradable program.
    #[account(
        mut,
        seeds = [crate::ID.as_ref()],
        bump,
        seeds::program = bpf_loader_upgradeable_program,
    )]
    program_data: AccountInfo<'info>,

    /// BPF Loader Upgradeable program.
    ///
    /// CHECK: In order to upgrade the program, we need to invoke the BPF Loader Upgradeable
    /// program.
    #[account(address = bpf_loader_upgradeable::id())]
    bpf_loader_upgradeable_program: AccountInfo<'info>,

    system_program: Program<'info, System>,
}

pub fn initialize(ctx: Context<Initialize>) -> Result<()> {
    ctx.accounts.custodian.set_inner(Custodian {
        bump: ctx.bumps.custodian,
        upgrade_authority_bump: ctx.bumps.upgrade_authority,
    });

    // Finally set the upgrade authority to this program's upgrade PDA.
    #[cfg(not(feature = "integration-test"))]
    {
        solana_program::program::invoke_signed(
            &bpf_loader_upgradeable::set_upgrade_authority_checked(
                &crate::ID,
                &ctx.accounts.deployer.key(),
                &ctx.accounts.upgrade_authority.key(),
            ),
            &ctx.accounts.to_account_infos(),
            &[&[
                UPGRADE_SEED_PREFIX,
                &[ctx.accounts.custodian.upgrade_authority_bump],
            ]],
        )?;
    }

    // Done.
    Ok(())
}
