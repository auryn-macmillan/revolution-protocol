# Developer Workflow

creds @ourzora

## Publishing the package; Generating changesets, versioning, building and Publishing.

Publishing happens in the following steps:

- Some changes are made to the repo; this can include smart contract changes or additions, if smart contracts are changed, tests should be created or updated to reflect the changes.
- The changes are committed to a branch which is **pushed** to **github**.
- A **pr** is **opened** for this branch.
- The changes are reviewed, if they are **approved**:
- _If there are changes to the smart contracts that should be deployed_: the contract should be. Deploying the contract results in the addresses of the deployed contracts being updated in the corresponding `./addresses/{chainId}.json` file. This file should be committed and pushed to github.
- Running the command `npx changeset` will generate **a new changeset** in the `./changesets` directory. This changeset will be used to determine the next version of the bundled packages; this commit should then be pushed.
- The changeset and smart contract addresses are pushed to the branch.
- The pr is merged into main - any changesets in the PR are detected by a github action `release`, which will then **open a new PR** with proper versions and readme updated in each each package. If more changesets are pushed to main before this branch is merged, the PR will continuously update the version of the packages according to the changeset specification.

7. That version is merged into main along with the new versions.

8. The package is then published to npm.

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
