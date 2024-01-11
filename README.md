# the Revolution protocol ⌐◨-◨

Revolution is a set of contracts that improve on [Nouns DAO](https://github.com/nounsDAO/nouns-monorepo). Nouns is a generative avatar collective that auctions off one ERC721, every day, forever. 100% of the proceeds of each auction (the winning bid) go into a shared treasury, and owning an NFT gets you 1 vote over the treasury.

<img width="377" alt="noun" src="https://github.com/collectivexyz/revolution-protocol/blob/main/readme-img/noun.png">

Compared to Nouns, Revolution seeks to make governance token ownership more accessible to creators and builders, and balance the scales between culture and capital while committing to a constant governance inflation schedule.

The ultimate goal of Revolution is fair ownership distribution over a community movement where anyone can earn decision making power over the energy of the movement. If this excites you, [build with us](mailto:rocketman@collective.xyz).

# Developer guide

## Setup

```
git clone https://github.com/collectivexyz/revolution-protocol.git && cd revolution-protocol
```

#### node.js and pnpm

```
npm install -g pnpm
```

#### Turbo

```
npm install turbo --global
```

#### Foundry

[Installation guide](https://book.getfoundry.sh/getting-started/installation)

## Install dependencies

```
pnpm install
```

## Run tests

Run tests for both Protocol Rewards and Revolution Contracts

```
turbo run test
```

Run tests in dev mode for a package w/gas logs

```
cd packages/revolution && pnpm run dev
```

## Gas reports

Gas reports are located in [gas-reports](https://github.com/collectivexyz/revolution-protocol/tree/main/gas-reports)

Run the tests with and generate a gas report.

```
cd packages/revolution && pnpm run write-gas-report
```

Gas optimizations around the CultureIndex `createPiece` and `vote` functionality, the [MaxHeap](https://github.com/collectivexyz/revolution-protocol/blob/main/packages/revolution/src/MaxHeap.sol) and [`buyToken`](https://github.com/collectivexyz/revolution-protocol/blob/main/packages/revolution/src/RevolutionPointsEmitter.sol) should be prioritized.

## Slither

#### Revolution contracts

Go into the Revolution directory (`cd packages/revolution`).

If `slither .` doesn't work, consider the following command:

```bash
slither src --checklist --show-ignored-findings --filter-paths "@openzeppelin|ERC721|Votes.sol|VotesUpgradeable.sol|ERC20Upgradeable.sol" --config-file="../../slither.config.json"
```

#### Protocol rewards

Go into the Protocol rewards directory (`cd packages/protocol-rewards`).

If `slither .` doesn't work, consider the following command:

```bash
slither src --checklist --show-ignored-findings --filter-paths "@openzeppelin" --config-file="../../slither.config.json"
```

# revolution overview

Instead of [auctioning](https://nouns.wtf/) off a generative PFP like Nouns, anyone can upload art pieces to the [CultureIndex](https://github.com/collectivexyz/revolution-protocol/blob/main/packages/revolution/src/CultureIndex.sol) contract, and the community votes on their favorite art pieces.

The top piece is auctioned off every day as an ERC721 [RevolutionToken](https://github.com/collectivexyz/revolution-protocol/blob/main/packages/revolution/src/RevolutionToken.sol) via the [AuctionHouse](https://github.com/collectivexyz/revolution-protocol/blob/main/packages/revolution/src/AuctionHouse.sol).

The auction proceeds are split with the creator(s) of the art piece, and the rest is sent to the owner of the auction contract. The winner of the auction receives an ERC721 of the art piece. The creator receives an amount of RevolutionPoints and a share of the winning bid.

The RevolutionPoints the creator receives is calculated by the [RevolutionPointsEmitter](https://github.com/collectivexyz/revolution-protocol/blob/main/packages/revolution/src/RevolutionPointsEmitter.sol). Both the ERC721 and the RevolutionPoints have voting power to vote on art pieces in the **CultureIndex**.

# relevant contracts

## CultureIndex

[**CultureIndex.sol**](https://github.com/collectivexyz/revolution-protocol/blob/main/packages/revolution/src/CultureIndex.sol) is a directory of uploaded art pieces that anyone can add media to. Owners of an ERC721 or RevolutionPoints can vote weighted by their balance on any given art piece.

<img width="817" alt="culture index" src="https://github.com/collectivexyz/revolution-protocol/blob/main/readme-img/culture-index.png">

The art piece votes data is stored in [**MaxHeap.sol**](https://github.com/collectivexyz/revolution-protocol/blob/main/packages/revolution/src/MaxHeap.sol), a heap datastructure that enables efficient lookups of the highest voted art piece.

The contract has a function called **dropTopVotedPiece**, only callable by the owner, which pops (removes) the top voted item from the **MaxHeap** and returns it.

## RevolutionToken

[**RevolutionToken.sol**](https://github.com/collectivexyz/revolution-protocol/blob/main/packages/revolution/src/RevolutionToken.sol) is a fork of the [NounsToken](https://github.com/nounsDAO/nouns-monorepo/blob/master/packages/nouns-contracts/contracts/NounsToken.sol) contract. **RevolutionToken** owns the **CultureIndex**. When calling **mint()** on the **RevolutionToken**, the contract calls **dropTopVotedPiece** on **CultureIndex**, and creates an ERC721 with metadata based on the dropped art piece data from the **CultureIndex**.

## AuctionHouse

[**AuctionHouse.sol**](https://github.com/collectivexyz/revolution-protocol/blob/main/packages/revolution/src/AuctionHouse.sol) is a fork of the [NounsAuctionHouse](https://github.com/nounsDAO/nouns-monorepo/blob/master/packages/nouns-contracts/contracts/NounsAuctionHouse.sol) contract, that mints **RevolutionToken**s. Additionally, the **AuctionHouse** splits auction proceeds (the winning bid) with the creator(s) of the art piece that is minted.

<img width="882" alt="Screenshot 2023-12-06 at 11 25 27 AM" src="https://github.com/collectivexyz/revolution-protocol/blob/main/readme-img/vrb-auction.png">

### Creator payment

The **creatorRateBps** defines the proportion (in basis points) of the auction proceeds that is reserved for the creator(s) of the art piece, called the _creator's share_.

```
creator_share = (msg.value * creatorRateBps) / 10_000
```

The **entropyRateBps** defines the proportion of the _creator's share_ that is sent to the creator directly in ether.

```
direct creator payment = (creator_share * entropyRateBps) / 10_000
```

The remaining amount of the _creator's share_ is sent to the [RevolutionPointsEmitter](https://github.com/collectivexyz/revolution-protocol/blob/main/packages/revolution/src/RevolutionPointsEmitter.sol) contract's **buyToken** function to buy the creator RevolutionPoints, according to a linear token emission schedule.

## RevolutionPointsEmitter

**[RevolutionPointsEmitter.sol](https://github.com/collectivexyz/revolution-protocol/blob/main/packages/revolution/src/RevolutionPointsEmitter.sol)** is a linear [VRGDA](https://www.paradigm.xyz/2022/08/vrgda) that mints RevolutionPoints when the payable **buyToken** function is called, and enables anyone to purchase RevolutionPoints at any time. A portion of value spent on buying the RevolutionPoints is paid to creators and to a protocol rewards contract.

### Creator payment

The RevolutionPointsEmitter has a **creatorRateBps** and **entropyRateBps** that function the same as the **AuctionHouse** contract's. Whenever a **buyToken** purchase of governance tokens is made, a **creatorRateBps** portion of the proceeds is reserved for the **creatorsAddress** set in the contract, with direct payment calculated according to the **entropyRateBps**.

### Protocol rewards

A fixed percentage of the value sent to the **buyToken** function is paid to the **PointsEmitterRewards** contract. The rewards setup is modeled after Zora's _fixed_ [protocol rewards](https://github.com/ourzora/zora-protocol/tree/main/packages/protocol-rewards). The key difference is that instead of a _fixed_ amount of ETH being split between the builder, referrer, deployer, and architect, the **PointsEmitterRewards** system splits a percentage of the value to relevant parties.

## VRGDA

The RevolutionPointsEmitter utilizes a VRGDA to emit RevolutionPoints at a predictable rate. You can read more about VRGDA's [here](https://www.paradigm.xyz/2022/08/vrgda), and view the implementation for selling NFTs [here](https://github.com/transmissions11/VRGDAs). Basically, a VRGDA contract dynamically adjusts the price of a token to adhere to a specific issuance schedule. If the emission is ahead of schedule, the price increases exponentially. If it is behind schedule, the price of each token decreases by some constant decay rate.

<img width="903" alt="Screenshot 2023-12-05 at 8 31 54 PM" src="https://github.com/collectivexyz/revolution-protocol/blob/main/readme-img/vrgda.png">

You can read more about the implementation on [Paradigm's site](https://www.paradigm.xyz/2022/08/vrgda). Additional information located in the Additional Context section of the README.

## Links

- **Previous Nouns DAO audits:**
- [NounsDAOV2](https://github.com/code-423n4/2022-08-nounsdao)
- [NounsDAOV3 (fork)](https://github.com/code-423n4/2023-07-nounsdao)
- **Twitter:**
  [@collectivexyz](https://twitter.com/collectivexyz) and [@vrbsdao](https://twitter.com/vrbsdao)

## Main invariants

(properties that should NEVER EVER be broken).

For all contracts - only the RevolutionBuilder manager should be able to initialize and upgrade them.

### RevolutionPoints

- Only the owner should be able to directly mint tokens.

- Tokens cannot be transferred between addresses (except to mint by the owner). This includes direct transfers, transfers from, and any other mechanisms that might move tokens between different addresses.

- No address should be able to approve another address to spend tokens on its behalf, as there should be no transfer of tokens.

- Only authorized entities (owner) should be able to mint new tokens. Minted tokens should correctly increase the recipient's balance and the total supply.

- Voting power and delegation work as intended according to [Votes](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/governance/utils/Votes.sol) without enabling any form of transferability.

### Creator payments

- The RevolutionPointsEmitter and AuctionHouse should always pay creators (ETH or RevolutionPoints) in accordance with the creatorRateBps and entropyRateBps calculation.

- The AuctionHouse should always pay only creator(s) of the CultureIndex art piece being auctioned and the owner.

- The RevolutionPointsEmitter should always pay the `creatorsAddress`.

- ETH and RevolutionPoints transfer functions are secure and protected with reentrancy checks / math errors.

### CultureIndex

- Anything uploaded to the CultureIndex should always be mintable by the RevolutionToken contract and not disrupt the RevolutionToken contract in any way.

- The voting weights calculated must be solely based on the ERC721 and RevolutionPoints balance of the account that casts the vote.

- Accounts should not be able to vote more than once on the same art piece with the same ERC721 token in the CultureIndex.

- Accounts can not vote twice on the same art piece.

- `voteWithSig` signatures should only be valid for a one-time use.

- Only snapshotted (at art piece creation block) vote weights should be able to update the total vote weight of the art piece. eg: If you received votes after snapshot date on the art piece, you should have 0 votes.

- CultureIndex and MaxHeap, must be resilient to DoS attacks that could significantly hinder voting, art creation, or auction processes.

- An art piece that has not met quorum cannot be dropped.

### RevolutionToken

- RevolutionToken should only mint art pieces from the CultureIndex.

- RevolutionToken should always mint the top voted art piece in the CultureIndex.

### AuctionHouse

- AuctionHouse should only auction off tokens from the RevolutionToken.
- The owner of the auction should always receive it's share of ether (minus creatorRateBps share).

### VRGDA

- The VRGDAC should always exponentially increase the price of tokens if the supply is ahead of schedule.

### RevolutionPointsEmitter

- The owner and creatorsAddress should not be able to buy tokens.

- The distribution of RevolutionPoints should be in accordance with the defined linear emission schedule.

- The RevolutionPointsEmitter should always pay protocol rewards assuming enough ETH was paid to the buyToken function.

- The owner should always receive it's share of ether (minus creatorRateBps and protocol rewards share).

# Additional Context

### VRGDAC

The Points Emitter utilizes a continuous VRGDA ([VRGDAC.sol](https://github.com/collectivexyz/revolution-protocol/blob/main/packages/revolution/src/libs/VRGDAC.sol)) to enable RevolutionPoints purchases. Given an amount of ether to pay, it will return the number of tokens to sell (`YtoX`), and given an amount of tokens to buy, will return the cost (`XtoY`) where X is the RevolutionPoints token and Y is ether. The original VRGDAC implementation is [here](https://gist.github.com/transmissions11/485a6e2deb89236202bd2f59796262fd).

In order to get the amount of tokens to emit given a payment of ether (`YtoX` in [VRGDAC.sol](https://github.com/collectivexyz/revolution-protocol/blob/main/packages/revolution/src/libs/VRGDAC.sol)), we first take the integral of the linear VRGDA pricing function [p(x)](https://www.paradigm.xyz/2022/08/vrgda).

<img width="487" alt="Screenshot 2023-12-05 at 9 21 59 PM" src="https://github.com/collectivexyz/revolution-protocol/blob/main/readme-img/vrgda-c-integral.png">

Then - we can get the cost of a specific number of tokens (`XtoY` in [VRGDAC.sol](https://github.com/collectivexyz/revolution-protocol/blob/main/packages/revolution/src/libs/VRGDAC.sol)) by doing `p_integral(x_start+x_bought) - p_integral(x_start)` where `x_start` is the current supply of the RevolutionPoints token and `x_bought` is the amount of tokens you wish to purchase.

We can then solve for `x_bought` using a handy python [solver](https://github.com/collectivexyz/revolution-protocol/blob/main/packages/revolution/script/solve.py) to find `YtoX`, allowing us to pass in an amount of ether and receive an amount of tokens to sell.

<img width="1727" alt="Screenshot 2023-12-05 at 8 34 22 PM" src="https://github.com/collectivexyz/revolution-protocol/blob/main/readme-img/vrgdac-graph.png">

The green line is the pricing function p(x) for a linear VRGDA. The red line is the integral of p(x), and the purple line signifies the amount of RevolutionPoints you'd receive given a payment in ether (YtoX). The relevant functions and integrals for the VRGDAC are available here: https://www.desmos.com/calculator/im67z1tate.
