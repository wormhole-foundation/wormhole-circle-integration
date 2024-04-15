use crate::{cctp::message_transmitter_program, error::WormholeCctpError, utils::CctpMessage};
use anchor_lang::prelude::*;
use wormhole_raw_vaas::cctp::WormholeCctpMessage;
use wormhole_solana_vaas::zero_copy::VaaAccount;

/// Method to reconcile a CCTP message with a Wormhole VAA encoding the Wormhole CCTP deposit. After
/// reconciliation, the method invokes the CCTP Message Transmitter to mint the local tokens to the
/// provided token account in the account context.
///
/// This method reconciles both messages by making sure the source domain, destination domain and
/// nonce match.
///
/// NOTE: It is the integrator's responsibility to ensure that the owner of this account is Wormhole
/// Core Bridge program if this method is used. Otherwise, please use [verify_vaa_and_mint], which
/// performs the account owner check.
pub fn verify_vaa_and_mint_unchecked<'info>(
    vaa: &VaaAccount<'_>,
    cctp_ctx: CpiContext<
        '_,
        '_,
        '_,
        'info,
        message_transmitter_program::cpi::ReceiveTokenMessengerMinterMessage<'info>,
    >,
    args: message_transmitter_program::cpi::ReceiveMessageArgs,
) -> Result<()> {
    let msg = WormholeCctpMessage::try_from(vaa.payload())
        .map_err(|_| error!(WormholeCctpError::CannotParseMessage))?;

    // This should always succeed. But we keep this check just in case we add more message types
    // in the future.
    let deposit = msg
        .deposit()
        .ok_or(error!(WormholeCctpError::InvalidDepositMessage))?;

    // We need to check the source domain, target domain and nonce to tie the Wormhole Circle Integration
    // message to the Circle message.
    let cctp_message = CctpMessage::parse(&args.encoded_message)
        .map_err(|_| WormholeCctpError::InvalidCctpMessage)?;

    require_eq!(
        deposit.source_cctp_domain(),
        cctp_message.source_domain(),
        WormholeCctpError::SourceCctpDomainMismatch
    );
    require_eq!(
        deposit.destination_cctp_domain(),
        cctp_message.destination_domain(),
        WormholeCctpError::DestinationCctpDomainMismatch
    );
    require_eq!(
        deposit.cctp_nonce(),
        cctp_message.nonce(),
        WormholeCctpError::CctpNonceMismatch
    );

    // This check is defense-in-depth (but can possibly be taken out in the future). We verify that
    // the mint recipient encoded in the deposit (the same one encoded in the CCTP message) is the
    // mint recipient token account found in the account context.
    require_keys_eq!(
        cctp_ctx.accounts.mint_recipient.key(),
        Pubkey::from(deposit.mint_recipient()),
        WormholeCctpError::InvalidMintRecipient
    );

    // Invoke CCTP Messasge Transmitter, which in this case performs a CPI call to the CCTP
    // Token Messenger Minter program to mint tokens.
    message_transmitter_program::cpi::receive_token_messenger_minter_message(cctp_ctx, args)?;

    // Done.
    Ok(())
}

/// Method to reconcile a CCTP message with a Wormhole VAA encoding the Wormhole CCTP deposit. After
/// reconciliation, the method invokes the CCTP Message Transmitter to mint the local tokens to the
/// provided token account in the account context. This method returns a zero-copy [VaaAccount]
/// reader so an integrator can verify emitter information.
///
/// This method reconciles both messages by making sure the source domain, destination domain and
/// nonce match.
///
/// NOTE: In order to return a zero-copy [VaaAccount] reader, this method takes a reference to the
/// [AccountInfo] of the VAA account.
pub fn verify_vaa_and_mint<'ctx, 'info>(
    vaa: &'ctx AccountInfo<'info>,
    cctp_ctx: CpiContext<
        '_,
        '_,
        '_,
        'info,
        message_transmitter_program::cpi::ReceiveTokenMessengerMinterMessage<'info>,
    >,
    args: message_transmitter_program::cpi::ReceiveMessageArgs,
) -> Result<VaaAccount<'ctx>> {
    // This is a very important check. We need to make sure that the VAA account is owned by the
    // Wormhole Core Bridge program. Otherwise, an attacker can create a fake VAA account.
    require_keys_eq!(
        *vaa.owner,
        crate::wormhole::core_bridge_program::id(),
        ErrorCode::ConstraintOwner
    );

    let vaa = VaaAccount::load(vaa)?;

    verify_vaa_and_mint_unchecked(&vaa, cctp_ctx, args)?;

    // Finally return the VAA account reader.
    Ok(vaa)
}
