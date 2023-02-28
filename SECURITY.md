# Security

The following document describes various aspects of the Wormhole Circle Integration security program.

## Table of Contents

- [3rd Party Security Audits](#3rd-Party-Security-Audits)
- [Bug Bounty Program](#Bug-Bounty-Program)

## 3rd Party Security Audits

At the time of writing, the wormhole circle integration project has not undergone any 3rd party security audits. However, in the future 3rd party firms shall be engaged to conduct independent security audits.

As these 3rd party audits are completed and issues are sufficiently addressed, we make those audit reports public.

- Q1 2023 - TBD

## Bug Bounty Program

Wormhole Circle Integration contracts are in scope for the [Wormhole Bug Bounty program](https://github.com/wormhole-foundation/wormhole/blob/main/SECURITY.md#bug-bounty-program).

If you find a security issue, please report the issue immediately using one of the two bug bounty programs above.

## Trust Assumptions

- Governance functionalities such as upgrading the contract and registering new emitter and domains relies entirely on Wormhole to verify a governance VAA. A governance VAA needs to be signed by atleast two-thirds of the Wormhole Guardian Set. In this case, the trust assumptions are the same as that of Wormhole- more details on which can be found [here](https://github.com/wormhole-foundation/wormhole/blob/main/SECURITY.md#trust-assumptions).
- Any initiated transfer emits both a Wormhole and a Circle message. To be redeemed, both the Wormhole and Circle messages need to pass signature verification. If only one of the two succeed, funds won’t be able to get redeemed. Hence, for transfer and redeeming, we rely on the integrity of not just the Circle bridge or Wormhole but on a combination of them both.
