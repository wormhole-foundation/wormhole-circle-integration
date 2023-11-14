use anchor_lang::prelude::*;

/// Account context to invoke [receive_token_messenger_minter_message].
#[derive(Accounts)]
pub struct ReceiveTokenMessengerMinterMessage<'info> {
    /// Mutable signer. Transaction payer.
    #[account(mut, signer)]
    pub payer: AccountInfo<'info>,

    /// Signer. Specific caller, which must be encoded as the destination caller.
    #[account(signer)]
    pub caller: AccountInfo<'info>,

    /// Seeds must be \["message_transmitter_authority"\] (CCTP Message Transmitter program).
    pub message_transmitter_authority: AccountInfo<'info>,

    /// Seeds must be \["message_transmitter"\] (CCTP Message Transmitter program).
    pub message_transmitter_config: AccountInfo<'info>,

    /// Mutable. Seeds must be \["used_nonces", remote_domain.to_string(), first_nonce.to_string()\]
    /// (CCTP Message Transmitter program).
    #[account(mut)]
    pub used_nonces: AccountInfo<'info>,

    /// CCTP Token Messenger Minter program.
    pub token_messenger_minter_program: AccountInfo<'info>,

    pub system_program: AccountInfo<'info>,

    // The following accounts are expected to be passed in as remaining accounts. These accounts are
    // meant for the Token Messenger Minter program because the Message Transmitter program performs
    // CPI on this program so it can mint tokens.
    //
    // For this integration, we are defining these accounts explicitly in this account context.

    //
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

    /// Seeds must be \["token_pair", remote_domain.to_string(), remote_token_address\] (CCTP Token
    /// Messenger Minter program).
    pub token_pair: AccountInfo<'info>,

    /// Mutable. Mint recipient token account, which must be encoded as the mint recipient in the
    /// CCTP mesage.
    #[account(mut)]
    pub mint_recipient: AccountInfo<'info>,

    /// Mutable. Seeds must be \["custody", mint\] (CCTP Token Messenger Minter program).
    #[account(mut)]
    pub custody_token: AccountInfo<'info>,

    pub token_program: AccountInfo<'info>,
}

/// Method to call the receive message instruction on the CCTP Message Transmitter program, specific
/// to receiving a Token Messenger Minter message to mint Circle-supported tokens.
///
/// NOTE: The [caller](ReceiveTokenMessengerMinterMessage::caller) account must be encoded in the
/// CCTP message as the destination caller.
pub fn receive_token_messenger_minter_message<'info>(
    ctx: CpiContext<'_, '_, '_, 'info, ReceiveTokenMessengerMinterMessage<'info>>,
    args: super::ReceiveMessageArgs,
) -> Result<()> {
    const ANCHOR_IX_SELECTOR: [u8; 8] = [38, 144, 127, 225, 31, 225, 238, 25];

    solana_program::program::invoke_signed(
        &solana_program::instruction::Instruction::new_with_borsh(
            crate::cctp::message_transmitter_program::ID,
            &(ANCHOR_IX_SELECTOR, args),
            ctx.to_account_metas(None),
        ),
        &ctx.to_account_infos(),
        ctx.signer_seeds,
    )
    .map_err(Into::into)
}
