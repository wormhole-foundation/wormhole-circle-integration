use anchor_lang::prelude::*;

/// Account context to invoke [receive_token_messenger_minter_message].
pub struct ReceiveTokenMessengerMinterMessage<'info> {
    /// Mutable signer. Transaction payer.
    pub payer: AccountInfo<'info>,

    /// Signer. Specific caller, which must be encoded as the destination caller.
    pub caller: AccountInfo<'info>,

    /// Seeds must be \["message_transmitter_authority"\, token_messenger_minter_program] (CCTP
    /// Message Transmitter program).
    pub message_transmitter_authority: AccountInfo<'info>,

    /// Seeds must be \["message_transmitter"\] (CCTP Message Transmitter program).
    pub message_transmitter_config: AccountInfo<'info>,

    /// Mutable. Seeds must be \["used_nonces", remote_domain.to_string(), first_nonce.to_string()\]
    /// (CCTP Message Transmitter program).
    pub used_nonces: AccountInfo<'info>,

    /// CCTP Token Messenger Minter program.
    pub token_messenger_minter_program: AccountInfo<'info>,

    pub system_program: AccountInfo<'info>,

    /// Seeds must be \["__event_authority"\] (CCTP Message Transmitter program)).
    pub message_transmitter_event_authority: AccountInfo<'info>,

    pub message_transmitter_program: AccountInfo<'info>,

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
    pub local_token: AccountInfo<'info>,

    /// Seeds must be \["token_pair", remote_domain.to_string(), remote_token_address\] (CCTP Token
    /// Messenger Minter program).
    pub token_pair: AccountInfo<'info>,

    /// Mutable. Mint recipient token account, which must be encoded as the mint recipient in the
    /// CCTP mesage.
    pub mint_recipient: AccountInfo<'info>,

    /// Mutable. Seeds must be \["custody", mint\] (CCTP Token Messenger Minter program).
    pub custody_token: AccountInfo<'info>,

    pub token_program: AccountInfo<'info>,

    /// Seeds must be \["__event_authority"\] (CCTP Token Messenger Minter program).
    pub token_messenger_minter_event_authority: AccountInfo<'info>,
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
        &solana_program::instruction::Instruction {
            program_id: crate::cctp::message_transmitter_program::ID,
            accounts: ctx.to_account_metas(None),
            data: (ANCHOR_IX_SELECTOR, args).try_to_vec()?,
        },
        &ctx.to_account_infos(),
        ctx.signer_seeds,
    )
    .map_err(Into::into)
}

impl<'info> ToAccountMetas for ReceiveTokenMessengerMinterMessage<'info> {
    fn to_account_metas(&self, _is_signer: Option<bool>) -> Vec<AccountMeta> {
        vec![
            AccountMeta::new(self.payer.key(), true),
            AccountMeta::new_readonly(self.caller.key(), true),
            AccountMeta::new_readonly(self.message_transmitter_authority.key(), false),
            AccountMeta::new_readonly(self.message_transmitter_config.key(), false),
            AccountMeta::new(self.used_nonces.key(), false),
            AccountMeta::new_readonly(self.token_messenger_minter_program.key(), false),
            AccountMeta::new_readonly(self.system_program.key(), false),
            AccountMeta::new_readonly(self.message_transmitter_event_authority.key(), false),
            AccountMeta::new_readonly(self.message_transmitter_program.key(), false),
            AccountMeta::new_readonly(self.token_messenger.key(), false),
            AccountMeta::new_readonly(self.remote_token_messenger.key(), false),
            AccountMeta::new_readonly(self.token_minter.key(), false),
            AccountMeta::new(self.local_token.key(), false),
            AccountMeta::new_readonly(self.token_pair.key(), false),
            AccountMeta::new(self.mint_recipient.key(), false),
            AccountMeta::new(self.custody_token.key(), false),
            AccountMeta::new_readonly(self.token_program.key(), false),
            AccountMeta::new_readonly(self.token_messenger_minter_event_authority.key(), false),
            AccountMeta::new_readonly(self.token_messenger_minter_program.key(), false),
        ]
    }
}

impl<'info> ToAccountInfos<'info> for ReceiveTokenMessengerMinterMessage<'info> {
    fn to_account_infos(&self) -> Vec<AccountInfo<'info>> {
        vec![
            self.payer.clone(),
            self.caller.clone(),
            self.message_transmitter_authority.clone(),
            self.message_transmitter_config.clone(),
            self.used_nonces.clone(),
            self.token_messenger_minter_program.clone(),
            self.system_program.clone(),
            self.message_transmitter_event_authority.clone(),
            self.token_messenger.clone(),
            self.remote_token_messenger.clone(),
            self.token_minter.clone(),
            self.local_token.clone(),
            self.token_pair.clone(),
            self.mint_recipient.clone(),
            self.custody_token.clone(),
            self.token_program.clone(),
            self.token_messenger_minter_event_authority.clone(),
        ]
    }
}
