use anchor_lang::prelude::*;

/// Account context to invoke [deposit_for_burn_with_caller].
#[derive(Accounts)]
pub struct DepositForBurnWithCaller<'info> {
    /// Signer. This account must be the owner of `src_token`.
    #[account(signer)]
    pub src_token_owner: AccountInfo<'info>,

    /// Seeds must be \["sender_authority"\] (CCTP Token Messenger Minter program).
    pub token_messenger_minter_sender_authority: AccountInfo<'info>,

    /// Mutable. This token account must be owned by `src_token_owner`.
    #[account(mut)]
    pub src_token: AccountInfo<'info>,

    /// Mutable. Seeds must be \["message_transmitter"\] (CCTP Message Transmitter program).
    #[account(mut)]
    pub message_transmitter_config: AccountInfo<'info>,

    /// Seeds must be \["token_messenger"\] (CCTP Token Messenger Minter program).
    pub token_messenger: AccountInfo<'info>,

    /// Seeds must be \["remote_token_messenger"\, remote_domain.to_string()] (CCTP Token Messenger
    /// Minter program).
    pub remote_token_messenger: AccountInfo<'info>,

    /// Seeds must be \["token_minter"\] (CCTP Token Messenger Minter program).
    pub token_minter: AccountInfo<'info>,

    /// Mutable. Seeds must be \["local_token", mint\] (CCTP Token Messenger Minter program).
    #[account(mut)]
    pub local_token: AccountInfo<'info>,

    /// Mutable. Mint to be burned via CCTP.
    #[account(mut)]
    pub mint: AccountInfo<'info>,

    /// CCTP Message Transmitter program.
    pub message_transmitter_program: AccountInfo<'info>,

    /// CCTP Token Messenger Minter program.
    pub token_messenger_minter_program: AccountInfo<'info>,

    pub token_program: AccountInfo<'info>,
}

/// Parameters to invoke [deposit_for_burn_with_caller].
#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct DepositForBurnWithCallerParams {
    /// Transfer (burn) amount.
    pub amount: u64,

    /// CCTP domain value of the token to be transferred.
    pub destination_domain: u32,

    /// Recipient of assets on target network.
    ///
    /// NOTE: In the Token Messenger Minter program IDL, this is encoded as a Pubkey, which is
    /// weird because this address is one for another network. We are making it a 32-byte fixed
    /// array instead.
    pub mint_recipient: [u8; 32],

    /// Expected caller on target network.
    ///
    /// NOTE: In the Token Messenger Minter program IDL, this is encoded as a Pubkey, which is
    /// weird because this address is one for another network. We are making it a 32-byte fixed
    /// array instead.
    pub destination_caller: [u8; 32],
}

/// CPI call to invoke the CCTP Token Messenger Minter program to burn Circle-supported assets.
///
/// NOTE: This instruction requires specifying a specific caller on the destination network. Only
/// this caller can mint tokens on behalf of the
/// [mint_recipient](DepositForBurnWithCallerParams::mint_recipient).
pub fn deposit_for_burn_with_caller<'info>(
    ctx: CpiContext<'_, '_, '_, 'info, DepositForBurnWithCaller<'info>>,
    args: DepositForBurnWithCallerParams,
) -> Result<()> {
    const ANCHOR_IX_SELECTOR: [u8; 8] = [167, 222, 19, 114, 85, 21, 14, 118];

    solana_program::program::invoke_signed(
        &solana_program::instruction::Instruction::new_with_borsh(
            crate::cctp::token_messenger_minter_program::ID,
            &(ANCHOR_IX_SELECTOR, args),
            ctx.to_account_metas(None),
        ),
        &ctx.to_account_infos(),
        ctx.signer_seeds,
    )
    .map_err(Into::into)
}
