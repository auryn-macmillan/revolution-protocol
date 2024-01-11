# @collectivexyz/revolution

## 0.3.1

### Patch Changes

- cafed37: make RevolutionPoints owned by the DAO Executor contract, and add a minter to it for the PointsEmitter

## 0.3.0

### Minor Changes

- 0398ceb: first round of audit fixes, adds DAO proxy contract and uses new VRGDA logic

### Patch Changes

- c32834b: fix high severity bug with VotesUpgradeable delegate functionality
- cbebcc5: make all contracts owned by DAO Executory, increases gas threshold
- Updated dependencies [0398ceb]
  - @cobuild/protocol-rewards@0.10.0

## 0.2.4

### Patch Changes

- ea77155: fix package org

## 0.2.3

### Patch Changes

- 6f1de66: adds tsup and tsconfig to enable publishing, uses new npm org

## 0.2.2

### Patch Changes

- 7f495d2: Token, culture index, and maxheap owned by DAO, adds new cultureindex dropper and maxheap admin

## 0.2.0

### Minor Changes

- 31feec1: added RevolutionBuilder to enable one function deployments of all revolution contracts. Made all contracts Initializable and creatable behind an ERC1967 proxy.
- 388aebf: adds voteWithSig to the cultureIndex. adds bidder param to AuctionHouse createBid function to enable paper checkout
- 611c162: renames batchVote to voteForMany and makes voteWithSig functions accept many pieceIds instead of one per

### Patch Changes

- Updated dependencies [31feec1]
  - @collectivexyz/protocol-rewards@0.2.0
