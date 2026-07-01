// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Project Configuration Guide
 * @author Your Name
 * @notice This file serves as a central place to document project configuration.
 * It contains the templates for `.gitignore` and `.env.example`, and provides guidance
 * on validating environment variables. This contract is not meant for deployment.
 */
contract ConfigHelper {
    /*

    ============================================================================
                                .gitignore
    ============================================================================

    # Dependency directories
    node_modules/

    # Environment variables file
    .env

    # Hardhat build and cache files
    artifacts/
    cache/
    coverage/
    coverage.json
    typechain-types/

    # Frontend build output
    dist/
    .vite/

    # Log files
    *.log

    # OS generated files
    .DS_Store
    Thumbs.db

    */

    /*

    ============================================================================
                              .env.example
    ============================================================================

    # --- Ethereum Wallet --- #
    # Your secret wallet private key. Used for deploying contracts and signing transactions.
    # IMPORTANT: NEVER commit this key to a public repository.
    # Example: "0x1234..."
    PRIVATE_KEY=""

    # --- RPC URLs --- #
    # URL for the Sepolia test network. Get one from Infura, Alchemy, QuickNode, etc.
    SEPOLIA_RPC_URL=""

    # (Optional) URL for the Ethereum Mainnet. Needed for mainnet deployments or forking.
    MAINNET_RPC_URL=""

    # --- Block Explorers --- #
    # Your API key for Etherscan. Used for automatic contract verification.
    ETHERSCAN_API_KEY=""

    # --- Gas Reporting --- #
    # (Optional) API key for CoinMarketCap. Used by hardhat-gas-reporter to display gas costs in USD.
    COINMARKETCAP_API_KEY=""

    # --- Frontend Configuration (Vite) --- #
    # These variables are exposed to the frontend application.
    # The `VITE_` prefix is required by Vite to expose them to `import.meta.env`.

    # Deployed address of the Staking contract.
    VITE_STAKING_CONTRACT=""

    # Deployed address of the NFT contract to be staked.
    VITE_NFT_CONTRACT=""

    # Deployed address of the ERC20 reward token contract.
    VITE_TOKEN_CONTRACT=""

    # Your project ID from WalletConnect Cloud (cloud.walletconnect.com).
    VITE_WALLET_CONNECT_PROJECT_ID=""

    */

    /*

    ============================================================================
                     Environment Variable Validation
    ============================================================================

    It's a best practice to validate required environment variables in your Hardhat config.
    Add this snippet at the top of your `hardhat.config.js` file to ensure the project
    is configured correctly before running any task.

    ----------------------------------------------------------------------------
    // Add this to the top of hardhat.config.js

    require("dotenv").config();

    const requiredEnvVars = ["PRIVATE_KEY", "SEPOLIA_RPC_URL", "ETHERSCAN_API_KEY"];

    for (const envVar of requiredEnvVars) {
        if (!process.env[envVar]) {
            throw new Error(`Error: Missing required environment variable ${envVar}`);
        }
    }
    ----------------------------------------------------------------------------

    */

    // This contract is intentionally left empty. It serves only as a documentation holder.
}