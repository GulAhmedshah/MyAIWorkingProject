const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

// Helper to parse ether
const parseEther = ethers.utils.parseEther;

// Test suite for the NFTStaking contract
describe("NFTStaking", function () {
    let nftStaking, rewardToken, myNFT;
    let owner, staker1, staker2, nonStaker;

    const REWARDS_PER_HOUR = parseEther("10"); // 10 tokens per hour

    beforeEach(async function () {
        // Get signers
        [owner, staker1, staker2, nonStaker] = await ethers.getSigners();

        // Deploy RewardToken (ERC20)
        const RewardToken = await ethers.getContractFactory("RewardToken");
        rewardToken = await RewardToken.deploy();
        await rewardToken.deployed();

        // Deploy MyNFT (ERC721)
        const MyNFT = await ethers.getContractFactory("MyNFT");
        myNFT = await MyNFT.deploy();
        await myNFT.deployed();

        // Deploy NFTStaking contract
        const NFTStaking = await ethers.getContractFactory("NFTStaking");
        nftStaking = await NFTStaking.deploy(myNFT.address, rewardToken.address);
        await nftStaking.deployed();

        // Set rewards per hour
        await nftStaking.connect(owner).setRewardsPerHour(REWARDS_PER_HOUR);

        // Fund the staking contract with reward tokens
        const totalRewards = parseEther("1000000");
        await rewardToken.connect(owner).transfer(nftStaking.address, totalRewards);

        // Mint NFTs for stakers
        // staker1 gets tokenIds 1, 2
        await myNFT.connect(owner).safeMint(staker1.address);
        await myNFT.connect(owner).safeMint(staker1.address);
        // staker2 gets tokenIds 3, 4
        await myNFT.connect(owner).safeMint(staker2.address);
        await myNFT.connect(owner).safeMint(staker2.address);
    });

    describe("Deployment", function () {
        it("Should set the right owner", async function () {
            expect(await nftStaking.owner()).to.equal(owner.address);
        });

        it("Should set the correct NFT and reward token addresses", async function () {
            expect(await nftStaking.nftContract()).to.equal(myNFT.address);
            expect(await nftStaking.rewardToken()).to.equal(rewardToken.address);
        });

        it("Should have the correct initial rewards per hour", async function () {
            expect(await nftStaking.rewardsPerHour()).to.equal(REWARDS_PER_HOUR);
        });

        it("Should have received the reward token funds", async function () {
            const balance = await rewardToken.balanceOf(nftStaking.address);
            expect(balance).to.be.gt(0);
        });
    });

    describe("Staking", function () {
        it("Should allow a user to stake an approved NFT", async function () {
            const tokenId = 1;
            await myNFT.connect(staker1).approve(nftStaking.address, tokenId);

            await expect(nftStaking.connect(staker1).stake([tokenId]))
                .to.emit(nftStaking, "Staked")
                .withArgs(staker1.address, [tokenId]);

            expect(await myNFT.ownerOf(tokenId)).to.equal(nftStaking.address);
            expect(await nftStaking.isStaked(tokenId)).to.be.true;
            const stakerInfo = await nftStaking.stakers(staker1.address);
            expect(stakerInfo.amountStaked).to.equal(1);
        });

        it("Should allow a user to stake multiple NFTs at once", async function () {
            const tokenIds = [1, 2];
            await myNFT.connect(staker1).setApprovalForAll(nftStaking.address, true);

            await expect(nftStaking.connect(staker1).stake(tokenIds))
                .to.emit(nftStaking, "Staked")
                .withArgs(staker1.address, tokenIds);

            expect(await myNFT.ownerOf(1)).to.equal(nftStaking.address);
            expect(await myNFT.ownerOf(2)).to.equal(nftStaking.address);
            const stakerInfo = await nftStaking.stakers(staker1.address);
            expect(stakerInfo.amountStaked).to.equal(2);
        });

        it("Should not allow staking without approval", async function () {
            const tokenId = 1;
            await expect(nftStaking.connect(staker1).stake([tokenId])).to.be.revertedWith(
                "ERC721: caller is not token owner or approved"
            );
        });

        it("Should not allow staking an already staked NFT", async function () {
            const tokenId = 1;
            await myNFT.connect(staker1).approve(nftStaking.address, tokenId);
            await nftStaking.connect(staker1).stake([tokenId]);

            await expect(nftStaking.connect(staker1).stake([tokenId])).to.be.revertedWith(
                "NFTStaking: Token already staked"
            );
        });

        it("Should not allow staking an NFT not owned by the caller", async function () {
            const tokenId = 3; // Owned by staker2
            await myNFT.connect(staker2).approve(nftStaking.address, tokenId);

            await expect(nftStaking.connect(staker1).stake([tokenId])).to.be.revertedWith(
                "NFTStaking: Caller is not the owner of the token"
            );
        });

        it("Should revert if staking an empty array of token IDs", async function () {
            await expect(nftStaking.connect(staker1).stake([])).to.be.revertedWith("NFTStaking: No token IDs provided");
        });
    });

    describe("Withdrawing", function () {
        beforeEach(async function () {
            const tokenIds = [1, 2];
            await myNFT.connect(staker1).setApprovalForAll(nftStaking.address, true);
            await nftStaking.connect(staker1).stake(tokenIds);
        });

        it("Should allow a staker to withdraw their own NFT", async function () {
            const tokenId = 1;
            await expect(nftStaking.connect(staker1).withdraw([tokenId]))
                .to.emit(nftStaking, "Withdrawn")
                .withArgs(staker1.address, [tokenId]);

            expect(await myNFT.ownerOf(tokenId)).to.equal(staker1.address);
            expect(await nftStaking.isStaked(tokenId)).to.be.false;
            const stakerInfo = await nftStaking.stakers(staker1.address);
            expect(stakerInfo.amountStaked).to.equal(1);
        });

        it("Should allow a staker to withdraw multiple NFTs", async function () {
            const tokenIds = [1, 2];
            await nftStaking.connect(staker1).withdraw(tokenIds);
            expect(await myNFT.ownerOf(1)).to.equal(staker1.address);
            expect(await myNFT.ownerOf(2)).to.equal(staker1.address);
            const stakerInfo = await nftStaking.stakers(staker1.address);
            expect(stakerInfo.amountStaked).to.equal(0);
        });

        it("Should not allow withdrawing an NFT not staked by the caller", async function () {
            const tokenId = 1;
            await expect(nftStaking.connect(staker2).withdraw([tokenId])).to.be.revertedWith(
                "NFTStaking: Caller is not the staker of this token"
            );
        });

        it("Should not allow withdrawing a non-staked NFT", async function () {
            const unstakedTokenId = 3;
            await expect(nftStaking.connect(staker2).withdraw([unstakedTokenId])).to.be.revertedWith(
                "NFTStaking: Token not staked"
            );
        });

        it("Should revert if withdrawing an empty array of token IDs", async function () {
            await expect(nftStaking.connect(staker1).withdraw([])).to.be.revertedWith("NFTStaking: No token IDs provided");
        });
    });

    describe("Rewards", function () {
        it("Should calculate rewards correctly for one staker", async function () {
            const tokenId = 1;
            await myNFT.connect(staker1).approve(nftStaking.address, tokenId);
            await nftStaking.connect(staker1).stake([tokenId]);

            // Increase time by 1 hour
            await time.increase(3600);

            const rewards = await nftStaking.calculateRewards(staker1.address);
            expect(rewards).to.equal(REWARDS_PER_HOUR);
        });

        it("Should allow a staker to claim rewards", async function () {
            const tokenId = 1;
            await myNFT.connect(staker1).approve(nftStaking.address, tokenId);
            await nftStaking.connect(staker1).stake([tokenId]);

            await time.increase(3600); // 1 hour

            const initialBalance = await rewardToken.balanceOf(staker1.address);
            const rewards = await nftStaking.calculateRewards(staker1.address);

            await expect(nftStaking.connect(staker1).claimRewards())
                .to.emit(nftStaking, "RewardsClaimed")
                .withArgs(staker1.address, rewards);

            const finalBalance = await rewardToken.balanceOf(staker1.address);
            expect(finalBalance.sub(initialBalance)).to.equal(rewards);

            // Unclaimed rewards should be (close to) zero after claiming
            const remainingRewards = await nftStaking.calculateRewards(staker1.address);
            expect(remainingRewards).to.be.closeTo(0, parseEther("0.0001"));
        });

        it("Should handle rewards for multiple stakers correctly", async function () {
            // Staker 1 stakes
            await myNFT.connect(staker1).approve(nftStaking.address, 1);
            await nftStaking.connect(staker1).stake([1]);
            const staker1StartTime = await time.latest();

            await time.increase(1800); // 30 minutes pass

            // Staker 2 stakes
            await myNFT.connect(staker2).approve(nftStaking.address, 3);
            await nftStaking.connect(staker2).stake([3]);

            await time.increase(1800); // another 30 minutes pass

            // Staker 1 has staked for 1 hour
            const rewards1 = await nftStaking.calculateRewards(staker1.address);
            expect(rewards1).to.be.closeTo(REWARDS_PER_HOUR, parseEther("0.001"));

            // Staker 2 has staked for 30 minutes
            const rewards2 = await nftStaking.calculateRewards(staker2.address);
            expect(rewards2).to.be.closeTo(REWARDS_PER_HOUR.div(2), parseEther("0.001"));
        });

        it("Should accumulate rewards correctly when staking more NFTs", async function () {
            // Staker 1 stakes 1 NFT
            await myNFT.connect(staker1).approve(nftStaking.address, 1);
            await nftStaking.connect(staker1).stake([1]);

            await time.increase(3600); // 1 hour passes
            // Rewards so far: 1 NFT * 1 hour * rate = 10 tokens

            // Staker 1 stakes another NFT
            await myNFT.connect(staker1).approve(nftStaking.address, 2);
            await nftStaking.connect(staker1).stake([2]);

            // Check that pending rewards were updated before state change
            const stakerInfo = await nftStaking.stakers(staker1.address);
            expect(stakerInfo.unclaimedRewards).to.be.closeTo(REWARDS_PER_HOUR, parseEther("0.001"));

            await time.increase(3600); // 1 more hour passes
            // Rewards for this period: 2 NFTs * 1 hour * rate = 20 tokens

            const totalRewards = await nftStaking.calculateRewards(staker1.address);
            // Total expected rewards = 10 (from first hour) + 20 (from second hour) = 30
            const expectedTotal = REWARDS_PER_HOUR.mul(3);
            expect(totalRewards).to.be.closeTo(expectedTotal, parseEther("0.001"));
        });

        it("Should reset pending rewards after withdrawing all NFTs", async function () {
            await myNFT.connect(staker1).approve(nftStaking.address, 1);
            await nftStaking.connect(staker1).stake([1]);
            await time.increase(3600);

            const rewardsBeforeWithdraw = await nftStaking.calculateRewards(staker1.address);

            // Withdraw all NFTs, which should also claim rewards
            await nftStaking.connect(staker1).withdrawAndClaim([1]);

            const finalRewards = await nftStaking.calculateRewards(staker1.address);
            expect(finalRewards).to.equal(0);

            const stakerInfo = await nftStaking.stakers(staker1.address);
            expect(stakerInfo.amountStaked).to.equal(0);
            expect(stakerInfo.unclaimedRewards).to.equal(0);

            // Check that rewards were transferred
            const stakerBalance = await rewardToken.balanceOf(staker1.address);
            expect(stakerBalance).to.be.closeTo(rewardsBeforeWithdraw, parseEther("0.001"));
        });

        it("Should not generate rewards if rewards per hour is zero", async function () {
            await nftStaking.connect(owner).setRewardsPerHour(0);
            
            await myNFT.connect(staker1).approve(nftStaking.address, 1);
            await nftStaking.connect(staker1).stake([1]);

            await time.increase(3600 * 10); // 10 hours

            const rewards = await nftStaking.calculateRewards(staker1.address);
            expect(rewards).to.equal(0);
        });
    });
});