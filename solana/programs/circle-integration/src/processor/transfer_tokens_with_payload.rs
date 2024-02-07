use crate::state::{Custodian, RegisteredEmitter};
use anchor_lang::prelude::*;
use anchor_spl::token;
use wormhole_cctp_solana::{
    cctp::{message_transmitter_program, token_messenger_minter_program},
    utils::ExternalAccount,
    wormhole::core_bridge_program,
};

/// Account context to invoke [transfer_tokens_with_payload].
#[derive(Accounts)]
pub struct TransferTokensWithPayload<'info> {
    #[account(mut)]
    payer: Signer<'info>,

    /// This program's Wormhole (Core Bridge) emitter authority.
    ///
    /// Seeds must be \["emitter"\].
    #[account(
        seeds = [Custodian::SEED_PREFIX],
        bump = custodian.bump,
    )]
    custodian: Account<'info, Custodian>,

    /// Circle-supported mint.
    ///
    /// CHECK: Mutable. This token account's mint must be the same as the one found in the CCTP
    /// Token Messenger Minter program's local token account.
    #[account(
        mut,
        address = local_token.mint,
    )]
    mint: AccountInfo<'info>,

    /// Token account where assets are burned from. The CCTP Token Messenger Minter program will
    /// burn the configured [amount](TransferTokensWithPayloadArgs::amount) from this account.
    ///
    /// NOTE: Transfer authority must be delegated to the custodian because this instruction
    /// transfers assets from this account to the custody token account.
    #[account(
        mut,
        token::mint = mint
    )]
    burn_source: Account<'info, token::TokenAccount>,

    /// Temporary custody token account. This account will be closed at the end of this instruction.
    /// It just acts as a conduit to allow this program to be the transfer initiator in the CCTP
    /// message.
    ///
    /// Seeds must be \["custody"\].
    #[account(
        init,
        payer = payer,
        token::mint = mint,
        token::authority = custodian,
        seeds = [crate::constants::CUSTODY_TOKEN_SEED_PREFIX],
        bump,
    )]
    custody_token: Account<'info, token::TokenAccount>,

    /// Registered emitter account representing a foreign Circle Integration emitter. This account
    /// exists only when another CCTP network is registered.
    ///
    /// Seeds must be \["registered_emitter", target_chain.to_be_bytes()\].
    #[account(
        seeds = [
            RegisteredEmitter::SEED_PREFIX,
            registered_emitter.chain.to_be_bytes().as_ref(),
        ],
        bump = registered_emitter.bump,
    )]
    registered_emitter: Account<'info, RegisteredEmitter>,

    /// CHECK: Seeds must be \["Bridge"\] (Wormhole Core Bridge program).
    #[account(mut)]
    core_bridge_config: UncheckedAccount<'info>,

    /// CHECK: Mutable signer to create Wormhole message account.
    #[account(mut)]
    core_message: Signer<'info>,

    /// CHECK: Mutable signer to create CCTP message.
    #[account(mut)]
    cctp_message: Signer<'info>,

    /// CHECK: Seeds must be \["Sequence"\, custodian] (Wormhole Core Bridge program).
    #[account(mut)]
    core_emitter_sequence: UncheckedAccount<'info>,

    /// CHECK: Seeds must be \["fee_collector"\] (Wormhole Core Bridge program).
    #[account(mut)]
    core_fee_collector: UncheckedAccount<'info>,

    /// CHECK: Seeds must be \["sender_authority"\] (CCTP Token Messenger Minter program).
    token_messenger_minter_sender_authority: UncheckedAccount<'info>,

    /// CHECK: Mutable. Seeds must be \["message_transmitter"\] (CCTP Message Transmitter program).
    #[account(mut)]
    message_transmitter_config: UncheckedAccount<'info>,

    /// CHECK: Seeds must be \["token_messenger"\] (CCTP Token Messenger Minter program).
    token_messenger: UncheckedAccount<'info>,

    /// CHECK: Seeds must be \["remote_token_messenger"\, remote_domain.to_string()] (CCTP Token
    /// Messenger Minter program).
    remote_token_messenger: UncheckedAccount<'info>,

    /// CHECK: Seeds must be \["token_minter"\] (CCTP Token Messenger Minter program).
    token_minter: UncheckedAccount<'info>,

    /// Local token account, which this program uses to validate the `mint` used to burn.
    ///
    /// Mutable. Seeds must be \["local_token", mint\] (CCTP Token Messenger Minter program).
    #[account(mut)]
    local_token: Box<Account<'info, ExternalAccount<token_messenger_minter_program::LocalToken>>>,

    /// CHECK: Seeds must be \["__event_authority"\] (CCTP Token Messenger Minter program).
    token_messenger_minter_event_authority: UncheckedAccount<'info>,

    core_bridge_program: Program<'info, core_bridge_program::CoreBridge>,
    token_messenger_minter_program:
        Program<'info, token_messenger_minter_program::TokenMessengerMinter>,
    message_transmitter_program: Program<'info, message_transmitter_program::MessageTransmitter>,
    token_program: Program<'info, token::Token>,
    system_program: Program<'info, System>,

    /// CHECK: Wormhole Core Bridge needs the clock sysvar based on its legacy implementation.
    #[account(address = solana_program::sysvar::clock::id())]
    clock: AccountInfo<'info>,

    /// CHECK: Wormhole Core Bridge needs the rent sysvar based on its legacy implementation.
    #[account(address = solana_program::sysvar::rent::id())]
    rent: AccountInfo<'info>,
}

/// Arguments used to invoke [transfer_tokens_with_payload].
#[derive(Debug, AnchorSerialize, AnchorDeserialize, Clone)]
pub struct TransferTokensWithPayloadArgs {
    /// Transfer (burn) amount.
    pub amount: u64,

    /// Recipient of assets on target network.
    pub mint_recipient: [u8; 32],

    /// Arbitrary value which may be meaningful to an integrator. This nonce is encoded in the
    /// Wormhole message.
    pub wormhole_message_nonce: u32,

    /// Arbitrary payload, which can be used to encode instructions or data for another network's
    /// smart contract.
    pub payload: Vec<u8>,
}

/// This instruction invokes both Wormhole Core Bridge and CCTP Token Messenger Minter programs to
/// emit a Wormhole message associated with a CCTP message.
///
/// See [burn_and_publish](wormhole_cctp_solana::cpi::burn_and_publish) for more details.
pub fn transfer_tokens_with_payload(
    ctx: Context<TransferTokensWithPayload>,
    args: TransferTokensWithPayloadArgs,
) -> Result<()> {
    let TransferTokensWithPayloadArgs {
        amount,
        mint_recipient,
        wormhole_message_nonce,
        payload,
    } = args;

    let custodian_seeds = &[Custodian::SEED_PREFIX, &[ctx.accounts.custodian.bump]];

    // Because the transfer initiator in the Circle message is whoever signs to burn assets, we need
    // to transfer assets from the source token account to one that belongs to this program.
    token::transfer(
        CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            token::Transfer {
                from: ctx.accounts.burn_source.to_account_info(),
                to: ctx.accounts.custody_token.to_account_info(),
                authority: ctx.accounts.custodian.to_account_info(),
            },
            &[custodian_seeds],
        ),
        amount,
    )?;

    wormhole_cctp_solana::cpi::burn_and_publish(
        CpiContext::new_with_signer(
            ctx.accounts
                .token_messenger_minter_program
                .to_account_info(),
            wormhole_cctp_solana::cpi::DepositForBurnWithCaller {
                burn_token_owner: ctx.accounts.custodian.to_account_info(),
                payer: ctx.accounts.payer.to_account_info(),
                token_messenger_minter_sender_authority: ctx
                    .accounts
                    .token_messenger_minter_sender_authority
                    .to_account_info(),
                burn_token: ctx.accounts.custody_token.to_account_info(),
                message_transmitter_config: ctx
                    .accounts
                    .message_transmitter_config
                    .to_account_info(),
                token_messenger: ctx.accounts.token_messenger.to_account_info(),
                remote_token_messenger: ctx.accounts.remote_token_messenger.to_account_info(),
                token_minter: ctx.accounts.token_minter.to_account_info(),
                local_token: ctx.accounts.local_token.to_account_info(),
                mint: ctx.accounts.mint.to_account_info(),
                cctp_message: ctx.accounts.cctp_message.to_account_info(),
                message_transmitter_program: ctx
                    .accounts
                    .message_transmitter_program
                    .to_account_info(),
                token_messenger_minter_program: ctx
                    .accounts
                    .token_messenger_minter_program
                    .to_account_info(),
                token_program: ctx.accounts.token_program.to_account_info(),
                system_program: ctx.accounts.system_program.to_account_info(),
                event_authority: ctx
                    .accounts
                    .token_messenger_minter_event_authority
                    .to_account_info(),
            },
            &[custodian_seeds],
        ),
        CpiContext::new_with_signer(
            ctx.accounts.core_bridge_program.to_account_info(),
            wormhole_cctp_solana::cpi::PostMessage {
                payer: ctx.accounts.payer.to_account_info(),
                message: ctx.accounts.core_message.to_account_info(),
                emitter: ctx.accounts.custodian.to_account_info(),
                config: ctx.accounts.core_bridge_config.to_account_info(),
                emitter_sequence: ctx.accounts.core_emitter_sequence.to_account_info(),
                fee_collector: ctx.accounts.core_fee_collector.to_account_info(),
                system_program: ctx.accounts.system_program.to_account_info(),
                clock: ctx.accounts.clock.to_account_info(),
                rent: ctx.accounts.rent.to_account_info(),
            },
            &[custodian_seeds],
        ),
        wormhole_cctp_solana::cpi::BurnAndPublishArgs {
            burn_source: Some(ctx.accounts.burn_source.key()),
            destination_caller: ctx.accounts.registered_emitter.address,
            destination_cctp_domain: ctx.accounts.registered_emitter.cctp_domain,
            amount,
            mint_recipient,
            wormhole_message_nonce,
            payload,
        },
    )?;

    // Finally close the custody token account.
    token::close_account(CpiContext::new_with_signer(
        ctx.accounts.token_program.to_account_info(),
        token::CloseAccount {
            account: ctx.accounts.custody_token.to_account_info(),
            destination: ctx.accounts.payer.to_account_info(),
            authority: ctx.accounts.custodian.to_account_info(),
        },
        &[custodian_seeds],
    ))
}
