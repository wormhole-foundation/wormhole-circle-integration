# Wormhole-Circle-Integration

Wormhole's Circle Integration smart contracts enable composable cross-chain transfers of Circle supported assets by pairing Circle's [Cross-Chain Transfer Protocol](https://www.circle.com/en/pressroom/circle-enables-usdc-interoperability-for-developers-with-the-launch-of-cross-chain-transfer-protocol) with Wormhole's generic-messaging layer.

## Prerequisites

### EVM

[Foundry tools](https://book.getfoundry.sh/getting-started/installation), which include `forge`, `anvil` and `cast` CLI tools, are a requirement for testing and deploying the Circle Integration smart contracts.

## Supported Blockchains

Currently, Circle's [Cross-Chain Transfer Protocol](https://www.circle.com/en/pressroom/circle-enables-usdc-interoperability-for-developers-with-the-launch-of-cross-chain-transfer-protocol) is only available for the Ethereum and Avalanche networks. Both of these chains are supported by Wormhole.

## Wormhole

See the [Wormhole monorepo](https://github.com/wormhole-foundation/wormhole) for more information about the reference implementation of the [Wormhole protocol](https://wormholenetwork.com).

⚠ **This software is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
implied. See the License for the specific language governing permissions and limitations under the License.** Or plainly
spoken - this is a very complex piece of software which targets a bleeding-edge, experimental smart contract runtime.
Mistakes happen, and no matter how hard you try and whether you pay someone to audit it, it may eat your tokens, set
your printer on fire or startle your cat. Cryptocurrencies are a high-risk investment, no matter how fancy.
