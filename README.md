# Foundry DeFi Stablecoin

# About

This project is meant to be a stablecoin where users can deposit WETH and WBTC in exchange for a token that will be pegged to the USD.


# Getting Started

## Requirements

- [git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
  - You'll know you did it right if you can run `git --version` and you see a response like `git version x.x.x`
- [foundry](https://getfoundry.sh/)
  - You'll know you did it right if you can run `forge --version` and you see a response like `forge 0.2.0 (816e00b 2023-03-16T00:05:26.396218Z)`

## Quickstart

```
git clone https://github.com/Cyfrin/foundry-defi-stablecoin-cu
cd foundry-defi-stablecoin-cu
forge build
```

# Updates

- The latest version of openzeppelin-contracts has changes in the ERC20Mock file. To follow along with the course, you need to install version 4.8.3 which can be done by `forge install openzeppelin/openzeppelin-contracts@v4.8.3 --no-commit` instead of `forge install openzeppelin/openzeppelin-contracts --no-commit`

## Testing

```
forge test
```

### Test Coverage

```
forge coverage
```

and for coverage based testing:

```
forge coverage --report debug
```

# Formatting

To run code formatting:

```
forge fmt
```

# Thank you!