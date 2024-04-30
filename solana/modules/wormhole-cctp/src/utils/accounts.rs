#[macro_export]
macro_rules! impl_anchor_account_readonly {
    ($anchor_acc:ty, $owner:expr, $disc:expr) => {
        impl anchor_lang::Owner for $anchor_acc {
            fn owner() -> anchor_lang::solana_program::pubkey::Pubkey {
                $owner
            }
        }
        impl anchor_lang::Discriminator for $anchor_acc {
            const DISCRIMINATOR: [u8; 8] = $disc;
        }

        impl anchor_lang::AccountDeserialize for $anchor_acc {
            fn try_deserialize(buf: &mut &[u8]) -> anchor_lang::Result<Self> {
                require!(
                    buf.len() >= 8,
                    anchor_lang::error::ErrorCode::AccountDidNotDeserialize
                );
                require!(
                    buf[..8] == <Self as anchor_lang::Discriminator>::DISCRIMINATOR,
                    anchor_lang::error::ErrorCode::AccountDiscriminatorMismatch,
                );
                Self::try_deserialize_unchecked(buf)
            }

            fn try_deserialize_unchecked(buf: &mut &[u8]) -> Result<Self> {
                Self::deserialize(&mut &buf[8..]).map_err(Into::into)
            }
        }

        impl anchor_lang::AccountSerialize for $anchor_acc {}
    };
}

pub use impl_anchor_account_readonly;
