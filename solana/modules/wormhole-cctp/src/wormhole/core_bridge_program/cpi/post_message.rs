use crate::wormhole::core_bridge_program::Commitment;
use anchor_lang::{prelude::*, system_program};
use wormhole_core_bridge_solana::state::Config;

#[derive(Accounts)]
pub struct PostMessage<'info> {
    #[account(mut)]
    pub config: AccountInfo<'info>,

    #[account(mut, signer)]
    pub message: AccountInfo<'info>,

    #[account(signer)]
    pub emitter: AccountInfo<'info>,

    #[account(mut)]
    pub emitter_sequence: AccountInfo<'info>,

    #[account(mut, signer)]
    pub payer: AccountInfo<'info>,

    #[account(mut)]
    pub fee_collector: AccountInfo<'info>,

    pub clock: AccountInfo<'info>,

    pub system_program: AccountInfo<'info>,

    pub rent: AccountInfo<'info>,
}

#[derive(Debug, AnchorSerialize, AnchorDeserialize, Clone)]
pub struct PostMessageArgs {
    /// Unique id for this message.
    pub nonce: u32,
    /// Encoded message.
    pub payload: Vec<u8>,
    /// Solana commitment level for Guardian observation.
    pub commitment: Commitment,
}

/// Processor to post (publish) a Wormhole message by setting up the message account for
/// Guardian observation.
///
/// A message is either created beforehand using the new Anchor instruction to process a message
/// or is created at this point.
pub fn post_message<'info>(
    ctx: CpiContext<'_, '_, '_, 'info, PostMessage<'info>>,
    args: PostMessageArgs,
) -> Result<()> {
    // Pay Wormhole message fee.
    {
        let mut data: &[_] = &ctx.accounts.config.try_borrow_data()?;
        let Config { fee_lamports, .. } = Config::deserialize(&mut data)?;

        system_program::transfer(
            CpiContext::new(
                ctx.accounts.system_program.to_account_info(),
                system_program::Transfer {
                    from: ctx.accounts.payer.to_account_info(),
                    to: ctx.accounts.fee_collector.to_account_info(),
                },
            ),
            fee_lamports,
        )?;
    }

    const IX_SELECTOR: u8 = 1;

    solana_program::program::invoke_signed(
        &solana_program::instruction::Instruction::new_with_borsh(
            crate::wormhole::core_bridge_program::id(),
            &(IX_SELECTOR, args),
            ctx.to_account_metas(None),
        ),
        &ctx.to_account_infos(),
        ctx.signer_seeds,
    )
    .map_err(Into::into)
}
