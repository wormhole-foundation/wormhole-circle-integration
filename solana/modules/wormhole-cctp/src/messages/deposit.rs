//! Messages relevant to the Token Bridge across all networks. These messages are serialized and
//! then published via the Core Bridge program.

use std::io;

use ruint::aliases::U256;
use wormhole_io::{Readable, TypePrefixedPayload, Writeable, WriteableBytes};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Deposit {
    pub token_address: [u8; 32],
    pub amount: U256,
    pub source_cctp_domain: u32,
    pub destination_cctp_domain: u32,
    pub cctp_nonce: u64,
    pub burn_source: [u8; 32],
    pub mint_recipient: [u8; 32],
    pub payload: WriteableBytes<u16>,
}

impl TypePrefixedPayload<1> for Deposit {
    const TYPE: Option<[u8; 1]> = Some([1]);

    fn written_size(&self) -> usize {
        32 // token_address
        + 32 // amount
        + 4 // source_cctp_domain
        + 4 // destination_cctp_domain
        + 8 // cctp_nonce
        + 32 // burn_source
        + 32 // mint_recipient
        + 2 // payload len
        + self.payload.len()
    }
}

impl Readable for Deposit {
    fn read<R>(reader: &mut R) -> io::Result<Self>
    where
        Self: Sized,
        R: io::Read,
    {
        Ok(Self {
            token_address: Readable::read(reader)?,
            amount: <[u8; 32]>::read(reader).map(U256::from_be_bytes)?,
            source_cctp_domain: Readable::read(reader)?,
            destination_cctp_domain: Readable::read(reader)?,
            cctp_nonce: Readable::read(reader)?,
            burn_source: Readable::read(reader)?,
            mint_recipient: Readable::read(reader)?,
            payload: Readable::read(reader)?,
        })
    }
}

impl Writeable for Deposit {
    fn write<W>(&self, writer: &mut W) -> std::io::Result<()>
    where
        Self: Sized,
        W: std::io::Write,
    {
        self.token_address.write(writer)?;
        self.amount.to_be_bytes::<32>().write(writer)?;
        self.source_cctp_domain.write(writer)?;
        self.destination_cctp_domain.write(writer)?;
        self.cctp_nonce.write(writer)?;
        self.burn_source.write(writer)?;
        self.mint_recipient.write(writer)?;
        self.payload.write(writer)?;
        Ok(())
    }
}

#[cfg(test)]
mod test {
    use hex_literal::hex;
    use wormhole_io::WriteableBytes;
    use wormhole_raw_vaas::cctp;

    use super::*;

    #[derive(Debug, Clone, PartialEq, Eq)]
    struct AllYourBase {
        pub are: u16,
        pub belong: u32,
        pub to: u64,
        pub us: WriteableBytes<u32>,
    }

    impl TypePrefixedPayload<2> for AllYourBase {
        const TYPE: Option<[u8; 2]> = Some([69, 69]);

        fn written_size(&self) -> usize {
            2 + 4 + 8 + 4 + self.us.len()
        }
    }

    impl Readable for AllYourBase {
        fn read<R>(reader: &mut R) -> io::Result<Self>
        where
            Self: Sized,
            R: io::Read,
        {
            Ok(Self {
                are: Readable::read(reader)?,
                belong: Readable::read(reader)?,
                to: Readable::read(reader)?,
                us: Readable::read(reader)?,
            })
        }
    }

    impl Writeable for AllYourBase {
        fn write<W>(&self, writer: &mut W) -> std::io::Result<()>
        where
            Self: Sized,
            W: std::io::Write,
        {
            self.are.write(writer)?;
            self.belong.write(writer)?;
            self.to.write(writer)?;
            self.us.write(writer)?;
            Ok(())
        }
    }

    #[test]
    fn serde() {
        let payload = AllYourBase {
            are: 42,
            belong: 1337,
            to: 9001,
            us: b"Beep boop".to_vec().try_into().unwrap(),
        };

        let deposit = Deposit {
            token_address: hex!("deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"),
            amount: U256::from(69420u64),
            source_cctp_domain: 5,
            destination_cctp_domain: 1,
            cctp_nonce: 69,
            burn_source: hex!("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
            mint_recipient: hex!(
                "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
            ),
            payload: payload.to_vec().try_into().unwrap(),
        };

        let encoded = deposit.to_vec();

        let msg = cctp::WormholeCctpMessage::parse(&encoded).unwrap();
        let parsed = msg.deposit().unwrap();

        let expected = Deposit {
            token_address: parsed.token_address(),
            amount: U256::from_be_bytes(parsed.amount()),
            source_cctp_domain: parsed.source_cctp_domain(),
            destination_cctp_domain: parsed.destination_cctp_domain(),
            cctp_nonce: parsed.cctp_nonce(),
            burn_source: parsed.burn_source(),
            mint_recipient: parsed.mint_recipient(),
            payload: payload.to_vec().try_into().unwrap(),
        };
        assert_eq!(deposit, expected);

        // Check for other encoded parameters.
        assert_eq!(
            usize::from(parsed.payload_len()),
            payload.payload_written_size()
        );

        // TODO: Recover by calling read_payload.
    }
}
