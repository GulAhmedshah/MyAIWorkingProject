const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("NFTStaking", function () {
    let NFTStaking, nftStaking;
    let TestNFT, testNFT;
    let RewardToken, rewardToken;
    let owner, addr1, addr2;

    // 10 tokens per second per NFT
    const REWARD_RATE = ethers.utils.parseUnits("10", 18);

    beforeEach(async function () {
        // Get signers
        [owner, addr1, addr2] = await ethers.getSigners();

        // Deploy RewardToken
        RewardToken = await ethers.getContractFactory("RewardToken");
        rewardToken = await RewardToken.deploy();
        await rewardToken.deployed();

        // Deploy TestNFT
        TestNFT = await ethers.getContractFactory("TestNFT");
        testNFT = await TestNFT.deploy();
        await testNFT.deployed();

        // Deploy NFTStaking contract
        NFTStaking = await ethers.getContractFactory("NFTStaking");
        nftStaking = await NFTStaking.deploy(rewardToken.address, testNFT.address, REWARD_RATE);
        await nftStaking.deployed();

        // Mint some NFTs for addr1 and addr2
        await testNFT.connect(owner).safeMint(addr1.address);
        await testNFT.connect(owner).safeMint(addr1.address);
        await testNFT.connect(owner).safeMint(addr2.address);
        // addr1 owns token IDs 0, 1
        // addr2 owns token ID 2

        // Approve the staking contract to manage users' NFTs
        await testNFT.connect(addr1).setApprovalForAll(nftStaking.address, true);
        await testNFT.connect(addr2).setApprovalForAll(nftStaking.address, true);

        // Fund the staking contract with reward tokens
        const totalRewards = ethers.utils.parseUnits("1000000", 18);
        await rewardToken.connect(owner).transfer(nftStaking.address, totalRewards);
    });

    describe("Deployment", function () {
        it("Should set the correct reward token address", async function () {
            expect(await nftStaking.rewardToken()).to.equal(rewardToken.address);
        });

        it("Should set the correct NFT address", async function () {
            expect(await nftStaking.nft()).to.equal(testNFT.address);
        });

        it("Should set the correct reward rate", async function () {
            expect(await nftStaking.rewardRate()).to.equal(REWARD_RATE);
        });

        it("Should have the correct balance of reward tokens", async function () {
            const totalRewards = ethers.utils.parseUnits("1000000", 18);
            expect(await rewardToken.balanceOf(nftStaking.address)).to.equal(totalRewards);
        });
    });

    describe("Staking", function () {
        it("Should allow a user to stake an NFT", async function () {
            const tokenId = 0;
            await expect(nftStaking.connect(addr1).stake([tokenId]))
                .to.emit(nftStaking, "Staked")
                .withArgs(addr1.address, [tokenId]);

            expect(await testNFT.ownerOf(tokenId)).to.equal(nftStaking.address);
            const stakerInfo = await nftStaking.stakers(addr1.address);
            expect(stakerInfo.stakedTokens.length).to.equal(1);
            expect(stakerInfo.stakedTokens[0]).to.equal(tokenId);
            expect(await nftStaking.stakedTokenOwner(tokenId)).to.equal(addr1.address);
        });

        it("Should not allow staking an already staked NFT", async function () {
            const tokenId = 0;
            await nftStaking.connect(addr1).stake([tokenId]);

            await expect(nftStaking.connect(addr1).stake([tokenId]))
                .to.be.revertedWith("NFTStaking: Token already staked");
        });

        it("Should not allow staking an NFT the user does not own", async function () {
            const tokenIdOwnedByAddr2 = 2;
            await expect(nftStaking.connect(addr1).stake([tokenIdOwnedByAddr2]))
                .to.be.revertedWith("NFTStaking: Caller is not the owner of the NFT");
        });

        it("Should not allow staking without prior approval", async function () {
            // Mint a new NFT to a new user who hasn't given approval
            const [,,, addr3] = await ethers.getSigners();
            await testNFT.connect(owner).safeMint(addr3.address); // tokenId 3
            const tokenId = 3;

            await expect(nftStaking.connect(addr3).stake([tokenId]))
                .to.be.revertedWith("ERC721: caller is not token owner or approved");
        });

        it("Should revert when staking an empty array", async function () {
            await expect(nftStaking.connect(addr1).stake([]))
                .to.be.revertedWith("NFTStaking: Must stake at least one token");
        });
    });

    describe("Withdrawing", function () {
        beforeEach(async function () {
            // addr1 stakes token 0
            await nftStaking.connect(addr1).stake([0]);
        });

        it("Should allow a user to withdraw a staked NFT", async function () {
            const tokenId = 0;
            await expect(nftStaking.connect(addr1).withdraw([tokenId]))
                .to.emit(nftStaking, "Withdrawn")
                .withArgs(addr1.address, [tokenId]);

            expect(await testNFT.ownerOf(tokenId)).to.equal(addr1.address);
            const stakerInfo = await nftStaking.stakers(addr1.address);
            expect(stakerInfo.stakedTokens.length).to.equal(0);
            expect(await nftStaking.stakedTokenOwner(tokenId)).to.equal(ethers.constants.AddressZero);
        });

        it("Should not allow a user to withdraw an NFT they did not stake", async function () {
            const tokenIdStakedByAddr1 = 0;
            await expect(nftStaking.connect(addr2).withdraw([tokenIdStakedByAddr1]))
                .to.be.revertedWith("NFTStaking: Caller did not stake this token");
        });

        it("Should not allow withdrawing an unstaked NFT", async function () {
            const unstakedTokenId = 1;
            await expect(nftStaking.connect(addr1).withdraw([unstakedTokenId]))
                .to.be.revertedWith("NFTStaking: Token not staked");
        });

        it("Should revert when withdrawing an empty array", async function () {
            await expect(nftStaking.connect(addr1).withdraw([]))
                .to.be.revertedWith("NFTStaking: Must withdraw at least one token");
        });
    });

    describe("Rewards", function () {
        it("Should calculate rewards correctly for a single staker", async function () {
            await nftStaking.connect(addr1).stake([0, 1]); // 2 NFTs
            
            const duration = 100; // 100 seconds
            await time.increase(duration);

            const expectedRewards = REWARD_RATE.mul(2).mul(duration);
            const calculatedRewards = await nftStaking.calculateRewards(addr1.address);
            expect(calculatedRewards).to.equal(expectedRewards);
        });

        it("Should allow a user to claim their rewards", async function () {
            await nftStaking.connect(addr1).stake([0]); // 1 NFT
            const duration = 60;
            await time.increase(duration);

            const rewards = await nftStaking.calculateRewards(addr1.address);
            const expectedRewards = REWARD_RATE.mul(1).mul(duration);
            expect(rewards).to.equal(expectedRewards);

            await expect(() => nftStaking.connect(addr1).claimRewards())
                .to.changeTokenBalance(rewardToken, addr1, expectedRewards);

            // Rewards should be reset after claiming
            expect(await nftStaking.calculateRewards(addr1.address)).to.equal(0);
        });

        it("Should handle rewards for multiple stakers correctly", async function () {
            // 1. addr1 stakes 2 NFTs
            await nftStaking.connect(addr1).stake([0, 1]);
            const initialTimestamp = await time.latest();

            // 2. Time passes for 100 seconds
            await time.increase(100);

            // 3. addr2 stakes 1 NFT
            await nftStaking.connect(addr2).stake([2]);

            // 4. Time passes for another 200 seconds
            await time.increase(200);

            // Calculate addr1's rewards
            // Staked 2 NFTs for a total of 300 seconds (100 + 200)
            const addr1ExpectedRewards = REWARD_RATE.mul(2).mul(300);
            const addr1CalculatedRewards = await nftStaking.calculateRewards(addr1.address);
            expect(addr1CalculatedRewards).to.equal(addr1ExpectedRewards);

            // Calculate addr2's rewards
            // Staked 1 NFT for 200 seconds
            const addr2ExpectedRewards = REWARD_RATE.mul(1).mul(200);
            const addr2CalculatedRewards = await nftStaking.calculateRewards(addr2.address);
            expect(addr2CalculatedRewards).to.equal(addr2ExpectedRewards);
        });

        it("Should automatically claim rewards on stake", async function () {
            await nftStaking.connect(addr1).stake([0]); // 1 NFT
            await time.increase(100);

            const expectedRewards = REWARD_RATE.mul(1).mul(100);
            const initialBalance = await rewardToken.balanceOf(addr1.address);

            // Staking another NFT should trigger claim
            await nftStaking.connect(addr1).stake([1]);

            const finalBalance = await rewardToken.balanceOf(addr1.address);
            expect(finalBalance.sub(initialBalance)).to.equal(expectedRewards);

            // Reward timer should be reset
            expect(await nftStaking.calculateRewards(addr1.address)).to.equal(0);
        });

        it("Should automatically claim rewards on withdraw", async function () {
            await nftStaking.connect(addr1).stake([0, 1]); // 2 NFTs
            await time.increase(100);

            const expectedRewards = REWARD_RATE.mul(2).mul(100);
            const initialBalance = await rewardToken.balanceOf(addr1.address);

            // Withdrawing an NFT should trigger claim
            await nftStaking.connect(addr1).withdraw([0]);

            const finalBalance = await rewardToken.balanceOf(addr1.address);
            expect(finalBalance.sub(initialBalance)).to.equal(expectedRewards);

            // Reward timer should be reset (for the remaining 1 NFT)
            expect(await nftStaking.calculateRewards(addr1.address)).to.equal(0);
        });

        it("Should revert if trying to claim zero rewards", async function () {
            await expect(nftStaking.connect(addr1).claimRewards())
                .to.be.revertedWith("NFTStaking: No rewards to claim");
            
            await nftStaking.connect(addr1).stake([0]);
            await expect(nftStaking.connect(addr1).claimRewards())
                .to.be.revertedWith("NFTStaking: No rewards to claim"); // Time hasn't passed
        });

        it("Should calculate rewards correctly after withdrawing all NFTs and restaking", async function(){
            // 1. Stake
            await nftStaking.connect(addr1).stake([0]);
            await time.increase(100);
            const firstReward = REWARD_RATE.mul(1).mul(100);

            // 2. Withdraw all (and claim rewards)
            const balanceBeforeWithdraw = await rewardToken.balanceOf(addr1.address);
            await nftStaking.connect(addr1).withdraw([0]);
            const balanceAfterWithdraw = await rewardToken.balanceOf(addr1.address);
            expect(balanceAfterWithdraw.sub(balanceBeforeWithdraw)).to.equal(firstReward);

            // 3. Wait some time (no rewards should accumulate)
            await time.increase(500);

            // 4. Re-stake
            await nftStaking.connect(addr1).stake([0]);
            await time.increase(200);

            // 5. Check rewards (should only be for the second staking period)
            const secondReward = REWARD_RATE.mul(1).mul(200);
            const calculatedRewards = await nftStaking.calculateRewards(addr1.address);
            expect(calculatedRewards).to.equal(secondReward);
        });
    });
});