use crate::{cctp, error::WormholeCctpError, messages::Deposit, wormhole::core_bridge_program};
use anchor_lang::prelude::*;
use wormhole_io::TypePrefixedPayload;

/// Arguments used to burn Circle-supported tokens and publish a Wormhole Core Bridge message.
#[derive(Debug, AnchorSerialize, AnchorDeserialize, Clone)]
pub struct BurnAndPublishArgs {
    /// Token account where assets originated from. This pubkey is encoded in the [Deposit] message.
    /// If this will be useful to an integrator, he should encode where the assets have been burned
    /// from if it was not burned directly when calling [burn_and_publish].
    pub burn_source: Option<Pubkey>,

    /// Destination caller address, which is encoded in the CCTP message. Only this address can
    /// receive a CCTP message via the CCTP Message Transmitter.
    pub destination_caller: [u8; 32],

    /// Destination CCTP domain, which is encoded both the Wormhole CCTP [Deposit] and CCTP
    /// messages. This domain indicates the intended foreign network.
    pub destination_cctp_domain: u32,

    /// Amount of tokens to burn.
    pub amount: u64,

    /// Intended mint recipient on destination network.
    pub mint_recipient: [u8; 32],

    /// Arbitrary value which may be meaningful to an integrator. This nonce is encoded in the
    /// Wormhole message.
    pub wormhole_message_nonce: u32,

    /// Arbitrary payload, which can be used to encode instructions or data for another network's
    /// smart contract.
    pub payload: Vec<u8>,
}

/// Method to publish a Wormhole Core Bridge message alongside a CCTP message that burns a
/// Circle-supported token.
///
/// NOTE: The [burn_source](BurnAndPublishArgs::burn_source) should be the token account where the
/// assets originated from. A program calling this method will not necessarily be burning assets
/// from this token account directly. So this field is used to indicate the origin of the burned
/// assets.
pub fn burn_and_publish<'info>(
    cctp_ctx: CpiContext<
        '_,
        '_,
        '_,
        'info,
        cctp::token_messenger_minter_program::cpi::DepositForBurnWithCaller<'info>,
    >,
    wormhole_ctx: CpiContext<'_, '_, '_, 'info, core_bridge_program::cpi::PostMessage<'info>>,
    args: BurnAndPublishArgs,
) -> Result<u64> {
    let BurnAndPublishArgs {
        burn_source,
        destination_caller,
        destination_cctp_domain,
        amount,
        mint_recipient,
        wormhole_message_nonce,
        payload,
    } = args;

    let cctp_nonce = {
        let mut data: &[_] = &cctp_ctx
            .accounts
            .message_transmitter_config
            .try_borrow_data()?;
        let config = cctp::message_transmitter_program::MessageTransmitterConfig::try_deserialize(
            &mut data,
        )?;

        // Publish message via Core Bridge. This includes paying the message fee.
        core_bridge_program::cpi::post_message(
            wormhole_ctx,
            core_bridge_program::cpi::PostMessageArgs {
                nonce: wormhole_message_nonce,
                payload: Deposit {
                    token_address: cctp_ctx.accounts.mint.key.to_bytes(),
                    amount: ruint::aliases::U256::from(amount),
                    source_cctp_domain: config.local_domain,
                    destination_cctp_domain,
                    cctp_nonce: config.next_available_nonce,
                    burn_source: burn_source
                        .unwrap_or(cctp_ctx.accounts.burn_token.key())
                        .to_bytes(),
                    mint_recipient,
                    payload: payload
                        .try_into()
                        .map_err(|_| WormholeCctpError::DepositMessageTooLarge)?,
                }
                .to_vec(),
                commitment: core_bridge_program::Commitment::Finalized,
            },
        )?;

        config.next_available_nonce
    };

    cctp::token_messenger_minter_program::cpi::deposit_for_burn_with_caller(
        cctp_ctx,
        cctp::token_messenger_minter_program::cpi::DepositForBurnWithCallerParams {
            amount,
            destination_domain: destination_cctp_domain,
            mint_recipient,
            destination_caller,
        },
    )?;

    Ok(cctp_nonce)
}
