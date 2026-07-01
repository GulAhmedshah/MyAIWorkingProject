
# NFT Staking Platform

![Build Status](https://github.com/your-username/nft-staking-platform/actions/workflows/ci.yml/badge.svg) ![Coverage Status](https://coveralls.io/repos/github/your-username/nft-staking-platform/badge.svg?branch=main) ![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)

A decentralized application (dApp) that allows users to stake their NFTs from a specific collection to earn rewards in the form of a custom ERC20 token.


## Project Overview

This platform provides a secure and efficient way for NFT holders to generate passive income. By staking their NFTs, users lock them in the smart contract and, in return, receive `RewardToken` ($RWT) based on the amount of time their NFTs are staked. The platform is managed by an owner who can configure reward parameters, ensuring a flexible and sustainable economic model.

## Architecture Diagram

A high-level overview of the contract interactions:


+-------+      (1) Stake NFT      +-----------------+      (3) Mint Rewards      +------------------+
| User  | ----------------------> | StakingContract | ------------------------> | RewardToken      |
+-------+      (approve, stake)   +-----------------+ <---(set approval)-----   +------------------+
    ^  ^                                    |                                      ^
    |  |                                    | (2) Transfer NFT from User           | (Minter Role)
    |  |                                    v                                      |
    |  +--(5) Claim Rewards, Unstake NFT     +-----------------+                     |
    |                                       |   NFTContract   |                     |
    +-----(4) Receive ERC20 Rewards         +-----------------+                     |


1.  **Stake:** The user first approves the `StakingContract` to manage their NFTs, then calls the `stake()` function.
2.  **NFT Transfer:** The `StakingContract` uses `safeTransferFrom` to securely hold the user's NFTs.
3.  **Reward Minting:** The `StakingContract`, granted a `MINTER_ROLE` on the `RewardToken` contract, mints new reward tokens as they are claimed.
4.  **Reward Distribution:** Claimed rewards are transferred to the user's wallet.
5.  **Unstake:** The user can unstake their NFTs at any time, which are then transferred back to their wallet.

## Features

- **Stake & Unstake:** Stake multiple NFTs in a single transaction. Unstake at any time.
- **Reward Accrual:** Rewards are calculated per second based on the number of NFTs staked.
- **Claim Rewards:** Claim accumulated rewards without needing to unstake.
- **Admin Controls:** Secure, owner-only functions to manage the reward rate and platform state (pausing/unpausing).
- **Security:** Built with OpenZeppelin's battle-tested contracts, includes Reentrancy Guard, Pausable functionality, and Ownable access control.
- **Gas Efficiency:** Optimized functions for staking, unstaking, and reward calculation to minimize gas costs for users.
- **Events:** Emits events for all major state changes (Staked, Unstaked, RewardPaid) for easy off-chain monitoring.


## Installation

To run this project locally, follow these steps:

1.  **Clone the repository:**
    sh
    git clone https://github.com/your-username/nft-staking-platform.git
    cd nft-staking-platform
    

2.  **Install dependencies:**
    sh
    npm install
    

3.  **Set up environment variables:**
    Create a `.env` file in the root directory and add the following, replacing the placeholder values:
    
    SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/YOUR_INFURA_PROJECT_ID
    PRIVATE_KEY=YOUR_WALLET_PRIVATE_KEY
    ETHERSCAN_API_KEY=YOUR_ETHERSCAN_API_KEY
    

## Smart Contract Documentation

The core logic is encapsulated in the following contracts:

-   `contracts/StakingContract.sol`: The main contract that handles all staking logic, reward calculations, and NFT custody.
-   `contracts/tokens/RewardToken.sol`: An ERC20 token used for rewards. It includes minting controls (`Ownable` or `AccessControl`).
-   `contracts/tokens/YourNFT.sol`: A sample ERC721 NFT contract that can be staked in the platform.

All contracts adhere to OpenZeppelin standards for security and clarity.


## Deployment

### Local Network

1.  Start a local Hardhat node:
    sh
    npx hardhat node
    

2.  In a new terminal, run the deployment script:
    sh
    npx hardhat run scripts/deploy.ts --network localhost
    

### Testnet (e.g., Sepolia)

1.  Ensure your `.env` file is configured with `SEPOLIA_RPC_URL` and `PRIVATE_KEY`.
2.  Run the deployment script:
    sh
    npx hardhat run scripts/deploy.ts --network sepolia
    
3.  After deployment, the script will output the contract addresses. Verify them on Etherscan using the command:
    sh
    npx hardhat verify --network sepolia <CONTRACT_ADDRESS> <CONSTRUCTOR_ARGS...>
    

### Deployed Contracts (Placeholders)

*   **Sepolia Testnet**:
    *   StakingContract: `[LINK TO SEPOLIA ETHERSCAN FOR STAKING CONTRACT]`
    *   RewardToken: `[LINK TO SEPOLIA ETHERSCAN FOR REWARD TOKEN]`
    *   YourNFT: `[LINK TO SEPOLIA ETHERSCAN FOR NFT CONTRACT]`

## Testing

Run the comprehensive test suite to ensure all functionality works as expected.

sh
npx hardhat test


To check test coverage:

sh
npx hardhat coverage


## Security Features

- **Reentrancy Guard:** The `claimRewards`, `stake`, and `unstake` functions are protected with OpenZeppelin's `ReentrancyGuard`.
- **Access Control:** Critical functions like `setRewardRate` and `pause` are restricted to the contract `owner` using `Ownable`.
- **Pausable:** The contract can be paused by the owner in case of an emergency, halting all staking, unstaking, and reward claims.
- **Input Validation:** Requires statements ensure function inputs are valid (e.g., non-zero token ID arrays).
- **ERC721Holder:** Prevents staked NFTs from being lost by implementing the standard `onERC721Received` hook.

## Monitoring

It is crucial to monitor the contract's activity on-chain. Key events to watch for:

-   `Staked(address indexed user, uint256[] tokenIds)`
-   `Unstaked(address indexed user, uint256[] tokenIds)`
-   `RewardPaid(address indexed user, uint256 reward)`
-   `RewardRateUpdated(uint256 newRate)`
-   `Paused(address account)` and `Unpaused(address account)`

Use services like **Tenderly** or **OpenZeppelin Defender** to set up real-time alerts for these events and for any failed transactions.

## API Documentation & Code Snippets

Below are the main functions of the `StakingContract`. All state-changing functions are non-reentrant.

### `stake(uint256[] calldata tokenIds)`
Stakes one or more NFTs for the message sender.
- **Prerequisites:** The user must first call `approve()` on the NFT contract for the `StakingContract` address.
- **Emits:** `Staked` event.
solidity
function stake(uint256[] calldata tokenIds) external whenNotPaused {
    // ... implementation
}


### `unstake(uint256[] calldata tokenIds)`
Unstakes one or more of the user's currently staked NFTs.
- **Note:** This function also automatically claims any pending rewards for the user before unstaking.
- **Emits:** `RewardPaid` and `Unstaked` events.
solidity
function unstake(uint256[] calldata tokenIds) external nonReentrant {
    // ... implementation
}


### `claimRewards()`
Claims all accumulated rewards for the message sender.
- **Emits:** `RewardPaid` event.
solidity
function claimRewards() external nonReentrant whenNotPaused {
    // ... implementation
}


### `calculateRewards(address user) returns (uint256)`
A view function to calculate the pending rewards for a given user.
solidity
function calculateRewards(address user) public view returns (uint256) {
    // ... implementation
}


### `setRewardRate(uint256 _rewardRate)`
An owner-only function to set the rewards distributed per NFT per second.
- **Emits:** `RewardRateUpdated` event.
solidity
function setRewardRate(uint256 _rewardRate) external onlyOwner {
    // ... implementation
}


### Other Functions
- `getStakedTokens(address user)`: Returns an array of token IDs currently staked by a user.
- `totalStaked()`: Returns the total number of NFTs currently staked in the contract.
- `pause()` / `unpause()`: Owner-only functions to pause and unpause the contract.

## Troubleshooting

- **Transaction fails on `stake()`:**
    -   Have you approved the Staking Contract to manage your NFTs? You must call `setApprovalForAll(stakingContractAddress, true)` on the NFT contract.
    -   Are you trying to stake an NFT you don't own?

- **Rewards are 0:**
    -   Has the contract owner set a `rewardRate` greater than zero?
    -   Is the contract currently paused?

- **`unstake()` fails:**
    -   Are you trying to unstake token IDs that are not staked by your address?

## Wallet Setup

To interact with the dApp, you need a Web3 wallet like MetaMask.

1.  **Install MetaMask:** Add the [MetaMask browser extension](https://metamask.io/download/).
2.  **Create/Import Account:** Set up a new wallet or import an existing one using your seed phrase.
3.  **Connect to Sepolia:** In MetaMask, click the network dropdown and select "Sepolia Test Network". If it's not listed, you may need to enable test networks in settings.
4.  **Get Test ETH:** You'll need Sepolia ETH to pay for gas fees. Use a public faucet like [sepoliafaucet.com](https://sepoliafaucet.com/).

## UI/Screenshots

*(Placeholders for screenshots of the frontend application)*

**Staking Interface:**
`[Screenshot of the main dApp page showing staking options and user's staked NFTs]`

**Transaction Confirmation:**
`[Screenshot of a MetaMask pop-up asking for confirmation to stake an NFT]`

## Contributing

Contributions are welcome! Please follow these steps:

1.  Fork the repository.
2.  Create a new feature branch (`git checkout -b feature/your-feature-name`).
3.  Make your changes and commit them (`git commit -m 'feat: add some feature'`).
4.  Push to the branch (`git push origin feature/your-feature-name`).
5.  Open a Pull Request.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

*/

/**
 * @dev This contract is a non-functional placeholder used to store the project's
 * README documentation within the repository in a way that satisfies specific
 * system constraints requiring a Solidity file format.
 * It is not intended for deployment or production use.
 */
contract ProjectReadme {
    string public constant PROJECT_NAME = "NFT Staking Platform";
    string public constant VERSION = "1.0.0";
}
