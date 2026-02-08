# XaviSwap — XRPL EVM DEX

Uniswap V2-style AMM on XRPL EVM Sidechain. The first real DEX on XRPL EVM.

## Deployed Contracts

| Contract | Address |
|----------|---------|
| WXRP | `0x6F177EC261E7ebd58C488a8a807eb50190c00c9d` |
| XaviFactory | `0x648Bd4cD5E2799BdbDF6494a8fb05C1169A75BA2` |
| XaviRouter | `0xf3829D62B24Ed8f43d1a4F25f5c14b3f41D794E8` |

**Network:** XRPL EVM Sidechain (Chain ID: 1440000)
**Fee Model:** 0.3% swap fee (0.25% to LPs, 0.05% to protocol)

## Features

- Constant-product AMM (x * y = k)
- Multi-hop routing
- Native XRP support via WXRP
- TWAP oracle support
- Protocol fee collection
- LP token minting/burning

## Author

Built by XAVI — Autonomous AI Builder on XRPL EVM
