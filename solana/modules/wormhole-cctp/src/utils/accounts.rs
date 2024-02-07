use anchor_lang::{prelude::*, Discriminator};

/// Wrapper for external account schemas, where an Anchor [Discriminator] and [Owner] are defined.
#[derive(Debug, AnchorSerialize, AnchorDeserialize, Clone)]
pub struct ExternalAccount<T>(T)
where
    T: AnchorSerialize + AnchorDeserialize + Clone + Discriminator + Owner;

impl<T> AccountDeserialize for ExternalAccount<T>
where
    T: AnchorSerialize + AnchorDeserialize + Clone + Discriminator + Owner,
{
    fn try_deserialize(buf: &mut &[u8]) -> Result<Self> {
        require!(buf.len() >= 8, ErrorCode::AccountDidNotDeserialize);
        require!(
            buf[..8] == T::DISCRIMINATOR,
            ErrorCode::AccountDiscriminatorMismatch,
        );
        Self::try_deserialize_unchecked(buf)
    }

    fn try_deserialize_unchecked(buf: &mut &[u8]) -> Result<Self> {
        Ok(Self(T::deserialize(&mut &buf[8..])?))
    }
}

impl<T> AccountSerialize for ExternalAccount<T> where
    T: AnchorSerialize + AnchorDeserialize + Clone + Discriminator + Owner
{
}

impl<T> Owner for ExternalAccount<T>
where
    T: AnchorSerialize + AnchorDeserialize + Clone + Discriminator + Owner,
{
    fn owner() -> Pubkey {
        T::owner()
    }
}

impl<T> std::ops::Deref for ExternalAccount<T>
where
    T: AnchorSerialize + AnchorDeserialize + Clone + Discriminator + Owner,
{
    type Target = T;

    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

/// Wrapper for external account schemas, where an Anchor [Discriminator] and [Owner] are defined.
#[derive(Debug, AnchorSerialize, AnchorDeserialize, Clone)]
pub struct BoxedExternalAccount<T>(Box<T>)
where
    T: AnchorSerialize + AnchorDeserialize + Clone + Discriminator + Owner;

impl<T> AccountDeserialize for BoxedExternalAccount<T>
where
    T: AnchorSerialize + AnchorDeserialize + Clone + Discriminator + Owner,
{
    fn try_deserialize(buf: &mut &[u8]) -> Result<Self> {
        require!(buf.len() >= 8, ErrorCode::AccountDidNotDeserialize);
        require!(
            buf[..8] == T::DISCRIMINATOR,
            ErrorCode::AccountDiscriminatorMismatch,
        );
        Self::try_deserialize_unchecked(buf)
    }

    fn try_deserialize_unchecked(buf: &mut &[u8]) -> Result<Self> {
        Ok(Self(Box::new(T::deserialize(&mut &buf[8..])?)))
    }
}

impl<T> AccountSerialize for BoxedExternalAccount<T> where
    T: AnchorSerialize + AnchorDeserialize + Clone + Discriminator + Owner
{
}

impl<T> Owner for BoxedExternalAccount<T>
where
    T: AnchorSerialize + AnchorDeserialize + Clone + Discriminator + Owner,
{
    fn owner() -> Pubkey {
        T::owner()
    }
}

impl<T> std::ops::Deref for BoxedExternalAccount<T>
where
    T: AnchorSerialize + AnchorDeserialize + Clone + Discriminator + Owner,
{
    type Target = T;

    fn deref(&self) -> &Self::Target {
        &self.0
    }
}
