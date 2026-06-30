const { expect } = require("chai");
const { ethers, hre } = require("hardhat");
const {
  loadFixture,
  time,
} = require("@nomicfoundation/hardhat-network-helpers");

describe("NFTStaking", function () {
  const REWARDS_PER_SECOND = ethers.utils.parseEther("10"); // 10 tokens per second
  const TOTAL_REWARD_SUPPLY = ethers.utils.parseEther("1000000"); // 1 million reward tokens

  // A fixture to reuse the same setup in every test.
  async function deployContractsFixture() {
    // Contracts are deployed using the first signer/account by default
    const [owner, staker1, staker2, otherAccount] = await ethers.getSigners();

    // Deploy Mock NFT (ERC721)
    const MyNFTFactory = await ethers.getContractFactory("MyNFT");
    const myNFT = await MyNFTFactory.deploy();

    // Deploy Mock Reward Token (ERC20)
    const RewardsTokenFactory = await ethers.getContractFactory("RewardsToken");
    const rewardsToken = await RewardsTokenFactory.deploy(TOTAL_REWARD_SUPPLY);

    // Deploy NFTStaking contract
    const NFTStakingFactory = await ethers.getContractFactory("NFTStaking");
    const nftStaking = await NFTStakingFactory.deploy(
      myNFT.address,
      rewardsToken.address
    );
    
    // Set the rewards per second
    await nftStaking.setRewardsPerSecond(REWARDS_PER_SECOND);
    
    // Transfer reward tokens to the staking contract to be distributed
    await rewardsToken.transfer(nftStaking.address, TOTAL_REWARD_SUPPLY);

    // Mint NFTs for stakers
    await myNFT.mint(staker1.address, 1);
    await myNFT.mint(staker1.address, 2);
    await myNFT.mint(staker2.address, 3);

    return {
      nftStaking,
      myNFT,
      rewardsToken,
      owner,
      staker1,
      staker2,
      otherAccount,
    };
  }

  // Before all tests, create and compile mock contracts for testing purposes
  before(async () => {
    // In a real project, these mocks would be in separate .sol files under contracts/test/ or contracts/mocks/
    const MyNFT = `
      // SPDX-License-Identifier: MIT
      pragma solidity ^0.8.19;
      import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
      contract MyNFT is ERC721 {
        constructor() ERC721("My Test NFT", "MTN") {}
        function mint(address to, uint256 tokenId) public {
          _mint(to, tokenId);
        }
      }
    `;
    const RewardsToken = `
      // SPDX-License-Identifier: MIT
      pragma solidity ^0.8.19;
      import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
      contract RewardsToken is ERC20 {
        constructor(uint256 initialSupply) ERC20("Rewards Token", "RWT") {
          _mint(msg.sender, initialSupply);
        }
      }
    `;
    const fs = require("fs");
    if (!fs.existsSync("contracts")) {
      fs.mkdirSync("contracts");
    }
    fs.writeFileSync("contracts/MyNFT.sol", MyNFT.trim());
    fs.writeFileSync("contracts/RewardsToken.sol", RewardsToken.trim());
    await hre.run("compile");
  });

  // After all tests, clean up the mock contract files
  after(async () => {
      const fs = require("fs");
      fs.unlinkSync("contracts/MyNFT.sol");
      fs.unlinkSync("contracts/RewardsToken.sol");
  });


  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      const { nftStaking, owner } = await loadFixture(deployContractsFixture);
      expect(await nftStaking.owner()).to.equal(owner.address);
    });

    it("Should set the correct NFT and reward token addresses", async function () {
      const { nftStaking, myNFT, rewardsToken } = await loadFixture(deployContractsFixture);
      expect(await nftStaking.nftAddress()).to.equal(myNFT.address);
      expect(await nftStaking.rewardsTokenAddress()).to.equal(rewardsToken.address);
    });

    it("Should set the correct rewards per second", async function () {
        const { nftStaking } = await loadFixture(deployContractsFixture);
        expect(await nftStaking.rewardsPerSecond()).to.equal(REWARDS_PER_SECOND);
    });
  });

  describe("Staking", function () {
    it("Should allow a user to stake an approved NFT", async function () {
      const { nftStaking, myNFT, staker1 } = await loadFixture(deployContractsFixture);
      const tokenId = 1;

      await myNFT.connect(staker1).approve(nftStaking.address, tokenId);

      const stakeTx = await nftStaking.connect(staker1).stake([tokenId]);
      const receipt = await stakeTx.wait();
      const block = await ethers.provider.getBlock(receipt.blockNumber);

      expect(await myNFT.ownerOf(tokenId)).to.equal(nftStaking.address);
      const stakerInfo = await nftStaking.getStakerInfo(staker1.address);
      expect(stakerInfo.amountStaked).to.equal(1);
      expect(stakerInfo.stakedTokens[0]).to.equal(tokenId);
      
      const stakedTokenInfo = await nftStaking.stakedTokens(tokenId);
      expect(stakedTokenInfo.staker).to.equal(staker1.address);
      expect(stakedTokenInfo.timestamp).to.equal(block.timestamp);

      await expect(stakeTx)
        .to.emit(nftStaking, "NFTStaked")
        .withArgs(staker1.address, tokenId, block.timestamp);
    });

    it("Should not allow staking an NFT without approval", async function () {
      const { nftStaking, staker1 } = await loadFixture(deployContractsFixture);
      const tokenId = 1;
      await expect(
        nftStaking.connect(staker1).stake([tokenId])
      ).to.be.revertedWith("ERC721: caller is not token owner nor approved");
    });
    
    it("Should not allow staking an NFT not owned by the caller", async function () {
        const { nftStaking, myNFT, staker1, staker2 } = await loadFixture(deployContractsFixture);
        const tokenId = 1; // Owned by staker1
  
        await myNFT.connect(staker1).approve(staker2.address, tokenId); // staker1 approves staker2
  
        await expect(
          nftStaking.connect(staker2).stake([tokenId]) // staker2 tries to stake staker1's NFT
        ).to.be.revertedWithCustomError(nftStaking, "NFTStaking__NotOwner");
    });

    it("Should not allow staking an already staked NFT", async function () {
      const { nftStaking, myNFT, staker1 } = await loadFixture(deployContractsFixture);
      const tokenId = 1;

      await myNFT.connect(staker1).approve(nftStaking.address, tokenId);
      await nftStaking.connect(staker1).stake([tokenId]);

      await expect(
        nftStaking.connect(staker1).stake([tokenId])
      ).to.be.revertedWithCustomError(nftStaking, "NFTStaking__AlreadyStaked");
    });
    
    it("Should reject staking with an empty array", async function () {
        const { nftStaking, staker1 } = await loadFixture(deployContractsFixture);
        await expect(nftStaking.connect(staker1).stake([])).to.be.revertedWithCustomError(
            nftStaking,
            "NFTStaking__NoTokensProvided"
        );
    });

    it("Should handle staking multiple NFTs", async function () {
        const { nftStaking, myNFT, staker1 } = await loadFixture(deployContractsFixture);
        const tokenIds = [1, 2];

        await myNFT.connect(staker1).approve(nftStaking.address, tokenIds[0]);
        await myNFT.connect(staker1).approve(nftStaking.address, tokenIds[1]);

        await nftStaking.connect(staker1).stake(tokenIds);

        expect(await myNFT.ownerOf(tokenIds[0])).to.equal(nftStaking.address);
        expect(await myNFT.ownerOf(tokenIds[1])).to.equal(nftStaking.address);

        const stakerInfo = await nftStaking.getStakerInfo(staker1.address);
        expect(stakerInfo.amountStaked).to.equal(2);
        expect(stakerInfo.stakedTokens).to.deep.equal(tokenIds.map(id => ethers.BigNumber.from(id)));
    });
  });

  describe("Rewards", function () {
    it("Should calculate rewards correctly for a single staker", async function () {
        const { nftStaking, myNFT, staker1 } = await loadFixture(deployContractsFixture);
        const tokenId = 1;
        
        await myNFT.connect(staker1).approve(nftStaking.address, tokenId);
        await nftStaking.connect(staker1).stake([tokenId]);
        
        const stakeDuration = 100; // seconds
        await time.increase(stakeDuration);
        
        const rewards = await nftStaking.calculateRewards(staker1.address);
        const expectedRewards = REWARDS_PER_SECOND.mul(stakeDuration);
        
        expect(rewards).to.equal(expectedRewards);
    });

    it("Should correctly calculate rewards for multiple staked NFTs", async function () {
        const { nftStaking, myNFT, staker1 } = await loadFixture(deployContractsFixture);
        const tokenIds = [1, 2];
    
        await myNFT.connect(staker1).approve(nftStaking.address, tokenIds[0]);
        await nftStaking.connect(staker1).stake([tokenIds[0]]);
        
        await time.increase(100); // 100 seconds pass
        
        await myNFT.connect(staker1).approve(nftStaking.address, tokenIds[1]);
        await nftStaking.connect(staker1).stake([tokenIds[1]]);
        
        await time.increase(100); // another 100 seconds pass
    
        const rewards = await nftStaking.calculateRewards(staker1.address);
        // NFT 1 staked for 200s, NFT 2 staked for 100s
        const expectedRewards = REWARDS_PER_SECOND.mul(200).add(REWARDS_PER_SECOND.mul(100));
    
        expect(rewards).to.be.closeTo(expectedRewards, ethers.utils.parseEther("0.001"));
    });

    it("Should handle multiple stakers correctly", async function () {
        const { nftStaking, myNFT, staker1, staker2 } = await loadFixture(deployContractsFixture);
        
        // Staker 1 stakes
        await myNFT.connect(staker1).approve(nftStaking.address, 1);
        await nftStaking.connect(staker1).stake([1]);
        
        await time.increase(50);
        
        // Staker 2 stakes
        await myNFT.connect(staker2).approve(nftStaking.address, 3);
        await nftStaking.connect(staker2).stake([3]);
        
        await time.increase(50);
        
        // Staker 1 has staked for 100 seconds (50 + 50)
        const rewards1 = await nftStaking.calculateRewards(staker1.address);
        const expectedRewards1 = REWARDS_PER_SECOND.mul(100);
        expect(rewards1).to.equal(expectedRewards1);
        
        // Staker 2 has staked for 50 seconds
        const rewards2 = await nftStaking.calculateRewards(staker2.address);
        const expectedRewards2 = REWARDS_PER_SECOND.mul(50);
        expect(rewards2).to.equal(expectedRewards2);
    });
  });

  describe("Claiming and Withdrawing", function () {
    it("Should allow a user to claim rewards without withdrawing", async function () {
        const { nftStaking, myNFT, rewardsToken, staker1 } = await loadFixture(deployContractsFixture);
        const tokenId = 1;
        
        await myNFT.connect(staker1).approve(nftStaking.address, tokenId);
        await nftStaking.connect(staker1).stake([tokenId]);
        
        const stakeDuration = 100;
        await time.increase(stakeDuration);
        
        const expectedRewards = REWARDS_PER_SECOND.mul(stakeDuration);

        const claimTx = nftStaking.connect(staker1).claimRewards();

        await expect(claimTx).to.changeTokenBalances(
            rewardsToken,
            [staker1, nftStaking],
            [expectedRewards, expectedRewards.mul(-1)]
        );
        
        // Rewards should be reset after claiming
        const rewardsAfterClaim = await nftStaking.calculateRewards(staker1.address);
        expect(rewardsAfterClaim).to.equal(0);
        
        // Staking info timestamp should be updated
        const stakeInfo = await nftStaking.stakedTokens(tokenId);
        const latestBlock = await ethers.provider.getBlock("latest");
        expect(stakeInfo.timestamp).to.equal(latestBlock.timestamp);
    });

    it("Should allow a user to withdraw a staked NFT and claim rewards", async function () {
        const { nftStaking, myNFT, rewardsToken, staker1 } = await loadFixture(deployContractsFixture);
        const tokenId = 1;
        
        await myNFT.connect(staker1).approve(nftStaking.address, tokenId);
        await nftStaking.connect(staker1).stake([tokenId]);
        
        const stakeDuration = 200;
        await time.increase(stakeDuration);

        const expectedRewards = REWARDS_PER_SECOND.mul(stakeDuration);
        
        const withdrawTx = await nftStaking.connect(staker1).withdraw([tokenId]);

        // Check NFT is returned
        expect(await myNFT.ownerOf(tokenId)).to.equal(staker1.address);

        // Check rewards are paid
        await expect(withdrawTx).to.changeTokenBalances(
            rewardsToken,
            [staker1, nftStaking],
            [expectedRewards, expectedRewards.mul(-1)]
        );
        
        // Check staking info is cleared
        const stakerInfo = await nftStaking.getStakerInfo(staker1.address);
        expect(stakerInfo.amountStaked).to.equal(0);
        const stakeInfo = await nftStaking.stakedTokens(tokenId);
        expect(stakeInfo.staker).to.equal(ethers.constants.AddressZero);

        await expect(withdrawTx)
            .to.emit(nftStaking, "NFTWithdrawn")
            .withArgs(staker1.address, tokenId);
    });

    it("Should not allow a non-staker to withdraw an NFT", async function () {
        const { nftStaking, myNFT, staker1, staker2 } = await loadFixture(deployContractsFixture);
        const tokenId = 1;

        await myNFT.connect(staker1).approve(nftStaking.address, tokenId);
        await nftStaking.connect(staker1).stake([tokenId]);
        
        await expect(nftStaking.connect(staker2).withdraw([tokenId]))
            .to.be.revertedWithCustomError(nftStaking, "NFTStaking__NotStaker");
    });

    it("Should not allow withdrawing a token that isn't staked", async function () {
        const { nftStaking, staker1 } = await loadFixture(deployContractsFixture);
        const tokenId = 99; // Not staked
        
        await expect(nftStaking.connect(staker1).withdraw([tokenId]))
            .to.be.revertedWithCustomError(nftStaking, "NFTStaking__NotStaked");
    });
    
    it("Should handle withdrawing multiple NFTs", async function () {
        const { nftStaking, myNFT, rewardsToken, staker1 } = await loadFixture(deployContractsFixture);
        const tokenIds = [1, 2];
        
        await myNFT.connect(staker1).setApprovalForAll(nftStaking.address, true);
        await nftStaking.connect(staker1).stake(tokenIds);
        
        const stakeDuration = 150;
        await time.increase(stakeDuration);

        const expectedRewards = REWARDS_PER_SECOND.mul(stakeDuration).mul(tokenIds.length);
        
        const withdrawTx = nftStaking.connect(staker1).withdraw(tokenIds);

        // Check NFTs are returned
        expect(await myNFT.ownerOf(tokenIds[0])).to.equal(staker1.address);
        expect(await myNFT.ownerOf(tokenIds[1])).to.equal(staker1.address);

        // Check rewards are paid
        await expect(withdrawTx).to.changeTokenBalances(
            rewardsToken,
            [staker1, nftStaking],
            [expectedRewards, expectedRewards.mul(-1)]
        );
        
        const stakerInfo = await nftStaking.getStakerInfo(staker1.address);
        expect(stakerInfo.amountStaked).to.equal(0);
    });

    it("Should reject withdrawing with an empty array", async function () {
        const { nftStaking, staker1 } = await loadFixture(deployContractsFixture);
        await expect(nftStaking.connect(staker1).withdraw([])).to.be.revertedWithCustomError(
            nftStaking,
            "NFTStaking__NoTokensProvided"
        );
    });
  });

  describe("Edge Cases and Security", function () {
    it("Should revert if trying to set zero address for NFT", async function () {
        const { nftStaking, rewardsToken } = await loadFixture(deployContractsFixture);
        const NFTStakingFactory = await ethers.getContractFactory("NFTStaking");
        await expect(NFTStakingFactory.deploy(
            ethers.constants.AddressZero,
            rewardsToken.address
        )).to.be.revertedWithCustomError(nftStaking, "NFTStaking__ZeroAddress");
    });
    
    it("Should revert if trying to set zero address for reward token", async function () {
        const { nftStaking, myNFT } = await loadFixture(deployContractsFixture);
        const NFTStakingFactory = await ethers.getContractFactory("NFTStaking");
        await expect(NFTStakingFactory.deploy(
            myNFT.address,
            ethers.constants.AddressZero
        )).to.be.revertedWithCustomError(nftStaking, "NFTStaking__ZeroAddress");
    });
    
    it("Should revert if non-owner tries to change rewards per second", async function () {
        const { nftStaking, staker1 } = await loadFixture(deployContractsFixture);
        const newRate = ethers.utils.parseEther("5");
        await expect(nftStaking.connect(staker1).setRewardsPerSecond(newRate))
            .to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("Should correctly update rewards for a staker after they claim", async function () {
        const { nftStaking, myNFT, staker1 } = await loadFixture(deployContractsFixture);
        const tokenId = 1;
        
        await myNFT.connect(staker1).setApprovalForAll(nftStaking.address, true);
        await nftStaking.connect(staker1).stake([tokenId]);
        
        await time.increase(100);
        await nftStaking.connect(staker1).claimRewards(); // Claim after 100s
        
        await time.increase(50); // Wait another 50s
        
        const rewards = await nftStaking.calculateRewards(staker1.address);
        const expectedRewards = REWARDS_PER_SECOND.mul(50); // Should only be for the last 50s
        
        expect(rewards).to.be.closeTo(expectedRewards, ethers.utils.parseEther("0.001"));
    });
    
    it("Should revert reward transfer if contract has insufficient balance", async function() {
        const { nftStaking, myNFT, rewardsToken, owner, staker1 } = await loadFixture(deployContractsFixture);
        
        // Drain the staking contract of its reward tokens
        const balance = await rewardsToken.balanceOf(nftStaking.address);
        await nftStaking.connect(owner).emergencyRewardWithdraw(balance);
        
        // Staker 1 stakes
        await myNFT.connect(staker1).setApprovalForAll(nftStaking.address, true);
        await nftStaking.connect(staker1).stake([1]);
        
        await time.increase(100);
        
        // Staker 1 tries to claim rewards
        await expect(nftStaking.connect(staker1).claimRewards())
            .to.be.revertedWith("ERC20: transfer amount exceeds balance");
    });
  });
});
