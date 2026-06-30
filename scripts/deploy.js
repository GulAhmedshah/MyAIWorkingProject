// scripts/deploy.js

// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const { ethers, network, run } = require("hardhat");

/**
 * @dev Main deployment script for the NFT Staking Platform.
 * This script performs the following actions:
 * 1. Deploys the `UtilityToken` ERC20 contract.
 * 2. Deploys a `MockNFT` ERC721 contract for demonstration purposes.
 * 3. Deploys the `NFTStaking` contract, linking the token and NFT contracts.
 * 4. Transfers a significant initial supply of `UtilityToken` to the `NFTStaking` contract to fund rewards.
 * 5. Logs all deployment information, including addresses and transaction hashes.
 * 6. Automatically verifies the deployed contracts on Etherscan for supported networks.
 */
async function main() {
  console.log(`\n🚀 Starting deployment on network: ${network.name}`);

  // Get the deployer account
  const [deployer] = await ethers.getSigners();
  console.log(`👨‍🚀 Deployer account: ${deployer.address}`);
  const deployerBalance = await deployer.getBalance();
  console.log(`💰 Account balance: ${ethers.utils.formatEther(deployerBalance)} ETH`);
  console.log("----------------------------------------------------");

  try {
    // --- 1. Deploy UtilityToken ---
    console.log("Deploying UtilityToken...");
    const UtilityTokenFactory = await ethers.getContractFactory("UtilityToken");
    // Gas estimation is handled automatically by Hardhat. For manual estimation or overrides, you can do:
    // const gasPrice = await ethers.provider.getGasPrice();
    // const utilityToken = await UtilityTokenFactory.deploy({ gasPrice: gasPrice });
    const utilityToken = await UtilityTokenFactory.deploy();
    await utilityToken.deployed();
    console.log(`✅ UtilityToken deployed to: ${utilityToken.address}`);

    // --- 2. Deploy MockNFT ---
    // For a real-world deployment, you would likely use an existing NFT collection's address.
    console.log("\nDeploying MockNFT...");
    const MockNFTFactory = await ethers.getContractFactory("MockNFT");
    const mockNFT = await MockNFTFactory.deploy();
    await mockNFT.deployed();
    console.log(`✅ MockNFT deployed to: ${mockNFT.address}`);

    // --- 3. Deploy NFTStaking ---
    console.log("\nDeploying NFTStaking...");
    const NFTStakingFactory = await ethers.getContractFactory("NFTStaking");
    const nftStaking = await NFTStakingFactory.deploy(
      utilityToken.address,
      mockNFT.address
    );
    await nftStaking.deployed();
    console.log(`✅ NFTStaking deployed to: ${nftStaking.address}`);
    console.log(`   - constructor args: [rewardToken: "${utilityToken.address}", nftCollection: "${mockNFT.address}"]`);
    
    // --- 4. Fund the Staking Contract ---
    console.log("\nFunding NFTStaking contract with reward tokens...");
    const initialRewardSupply = ethers.utils.parseUnits("1000000", 18); // 1 Million tokens
    const transferTx = await utilityToken.transfer(
      nftStaking.address,
      initialRewardSupply
    );
    await transferTx.wait(1); // Wait for 1 block confirmation
    console.log(`✅ Transferred ${ethers.utils.formatUnits(initialRewardSupply)} UT tokens to the staking contract.`);
    console.log(`   - tx hash: ${transferTx.hash}`);

    console.log("\n🎉 All contracts deployed and configured successfully! 🎉");
    console.log("----------------------------------------------------");

    // --- 5. Verify Contracts on Etherscan ---
    // The script will automatically attempt to verify on Etherscan-like explorers
    // if the network is not a local development network.
    if (network.config.chainId && network.name !== "hardhat" && network.name !== "localhost") {
      console.log("\nWaiting for 5 block confirmations before starting verification...");
      // For Etherscan, it's good practice to wait for a few blocks
      await utilityToken.deployTransaction.wait(5);
      await mockNFT.deployTransaction.wait(5);
      await nftStaking.deployTransaction.wait(5);

      // Verification comment: The helper function below automates contract verification.
      await verify(utilityToken.address, []);
      await verify(mockNFT.address, []);
      await verify(nftStaking.address, [
        utilityToken.address,
        mockNFT.address,
      ]);
    }

  } catch (error) {
    console.error("\n❌ Deployment failed:", error);
    process.exitCode = 1;
  }
}

/**
 * @dev Helper function to verify contracts on Etherscan.
 * @param contractAddress The address of the contract to verify.
 * @param args The constructor arguments of the contract.
 */
const verify = async (contractAddress, args) => {
  console.log(`\nVerifying contract at ${contractAddress}...`);
  try {
    await run("verify:verify", {
      address: contractAddress,
      constructorArguments: args,
    });
    console.log(`   ✅ Contract verified successfully!`);
  } catch (e) {
    if (e.message.toLowerCase().includes("already verified")) {
      console.log("   ✅ Contract is already verified.");
    } else {
      console.log(`   ❌ Verification failed: ${e.message}`);
    }
  }
};

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

// Export the main function for potential use in other scripts or tests
module.exports.deploy = main;
