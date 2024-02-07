mod posted_vaa_v1;
pub use posted_vaa_v1::*;

use anchor_lang::prelude::*;
use wormhole_raw_vaas::Payload;

#[non_exhaustive]
pub enum VaaAccount<'a> {
    PostedVaaV1(PostedVaaV1<'a>),
}

#[derive(Debug, AnchorSerialize, AnchorDeserialize, Copy, Clone)]
pub struct EmitterInfo {
    pub chain: u16,
    pub address: [u8; 32],
    pub sequence: u64,
}

impl<'a> VaaAccount<'a> {
    pub fn version(&'a self) -> u8 {
        match self {
            Self::PostedVaaV1(_) => 1,
        }
    }

    pub fn try_emitter_info(&self) -> Result<EmitterInfo> {
        match self {
            Self::PostedVaaV1(inner) => Ok(EmitterInfo {
                chain: inner.emitter_chain(),
                address: inner.emitter_address(),
                sequence: inner.sequence(),
            }),
        }
    }

    pub fn try_emitter_chain(&self) -> Result<u16> {
        match self {
            Self::PostedVaaV1(inner) => Ok(inner.emitter_chain()),
        }
    }

    pub fn try_emitter_address(&self) -> Result<[u8; 32]> {
        match self {
            Self::PostedVaaV1(inner) => Ok(inner.emitter_address()),
        }
    }

    pub fn try_timestamp(&self) -> Result<u32> {
        match self {
            Self::PostedVaaV1(inner) => Ok(inner.timestamp()),
        }
    }

    pub fn try_payload(&self) -> Result<Payload> {
        match self {
            Self::PostedVaaV1(inner) => Ok(Payload::parse(inner.payload())),
        }
    }

    pub fn try_digest(&self) -> Result<solana_program::keccak::Hash> {
        match self {
            Self::PostedVaaV1(inner) => Ok(inner.digest()),
        }
    }

    pub fn posted_vaa_v1(&'a self) -> Option<&'a PostedVaaV1<'a>> {
        match self {
            Self::PostedVaaV1(inner) => Some(inner),
        }
    }

    pub fn load(acc_info: &'a AccountInfo) -> Result<Self> {
        let data = acc_info.try_borrow_data()?;
        require!(data.len() > 8, ErrorCode::AccountDidNotDeserialize);

        match <[u8; 8]>::try_from(&data[..8]).unwrap() {
            [118, 97, 97, 1, _, _, _, _] => Ok(Self::PostedVaaV1(PostedVaaV1::new(acc_info)?)),
            _ => err!(ErrorCode::AccountDidNotDeserialize),
        }
    }
}
