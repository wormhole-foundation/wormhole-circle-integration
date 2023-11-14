/// Circle Message generated by the Message Transmitter program.
///
/// See https://developers.circle.com/stablecoins/docs/message-format for more info.
#[derive(Debug, Copy, Clone, PartialEq, Eq, Hash)]
pub struct CctpMessage<'a> {
    span: &'a [u8],
}

impl AsRef<[u8]> for CctpMessage<'_> {
    fn as_ref(&self) -> &[u8] {
        self.span
    }
}

impl<'a> CctpMessage<'a> {
    pub fn version(&self) -> u32 {
        u32::from_be_bytes(self.span[..4].try_into().unwrap())
    }

    pub fn source_domain(&self) -> u32 {
        u32::from_be_bytes(self.span[4..8].try_into().unwrap())
    }

    pub fn destination_domain(&self) -> u32 {
        u32::from_be_bytes(self.span[8..12].try_into().unwrap())
    }

    pub fn nonce(&self) -> u64 {
        u64::from_be_bytes(self.span[12..20].try_into().unwrap())
    }

    pub fn sender(&self) -> [u8; 32] {
        self.span[20..52].try_into().unwrap()
    }

    pub fn recipient(&self) -> [u8; 32] {
        self.span[52..84].try_into().unwrap()
    }

    pub fn destination_caller(&self) -> [u8; 32] {
        self.span[84..116].try_into().unwrap()
    }

    pub fn message(&self) -> &[u8] {
        &self.span[116..]
    }

    pub fn parse(span: &'a [u8]) -> Result<CctpMessage<'a>, &'static str> {
        if span.len() < 116 {
            return Err("CctpMessage span too short. Need at least 116 bytes");
        }

        Ok(CctpMessage { span })
    }
}
