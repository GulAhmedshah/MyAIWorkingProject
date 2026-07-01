// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title NFT Staking Platform
 * @author Your Name
 * @notice This contract allows users to stake NFTs (ERC721) and earn rewards in an ERC20 token.
 * @dev It includes functionalities for staking, unstaking, claiming rewards, and provides view functions
 * to support a rich user interface, including total staked assets, user-specific stats, and reward calculations.
 */
contract Staking is Ownable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.UintSet;

    // --- State Variables ---

    // Struct to store information about each staker
    struct Staker {
        uint256 amountStaked;
        uint256 rewardPerTokenPaid;
        uint256 rewards;
    }

    // --- Immutable Variables ---
    IERC721 public immutable nftCollection;
    IERC20 public immutable rewardsToken;

    // --- Staking Data ---
    uint256 public totalStaked;
    mapping(address => Staker) private stakers;
    mapping(address => EnumerableSet.UintSet) private stakedTokens;
    mapping(uint256 => address) public stakerOf;

    // --- Reward Data ---
    uint256 public rewardRate; // Rewards per second for the entire pool
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public totalRewardsPaidOut;

    // --- Events ---

    /**
     * @notice Emitted when a new reward rate is set.
     * @param newRate The new reward rate in tokens per second.
     */
    event RewardRateUpdated(uint256 newRate);

    /**
     * @notice Emitted when a user stakes one or more NFTs.
     * @param user The address of the staker.
     * @param tokenId The ID of the staked NFT.
     */
    event Staked(address indexed user, uint256 indexed tokenId);

    /**
     * @notice Emitted when a user unstakes one or more NFTs.
     * @param user The address of the unstaker.
     * @param tokenId The ID of the unstaked NFT.
     */
    event Unstaked(address indexed user, uint256 indexed tokenId);

    /**
     * @notice Emitted when a user claims their earned rewards.
     * @param user The address of the user claiming rewards.
     * @param rewardAmount The amount of rewards tokens claimed.
     */
    event RewardsClaimed(address indexed user, uint256 rewardAmount);

    // --- Modifiers ---

    /**
     * @dev Modifier to update reward calculations for a user before a state change.
     * @param _user The user address to update rewards for.
     */
    modifier updateReward(address _user) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;
        stakers[_user].rewards = earned(_user);
        stakers[_user].rewardPerTokenPaid = rewardPerTokenStored;
        _;
    }

    // --- Constructor ---

    /**
     * @notice Sets up the staking contract with the NFT and rewards token addresses.
     * @param _nftCollectionAddress The address of the ERC721 NFT contract.
     * @param _rewardsTokenAddress The address of the ERC20 rewards token contract.
     */
    constructor(address _nftCollectionAddress, address _rewardsTokenAddress) {
        if (_nftCollectionAddress == address(0) || _rewardsTokenAddress == address(0)) {
            revert("Staking: Zero address provided");
        }
        nftCollection = IERC721(_nftCollectionAddress);
        rewardsToken = IERC20(_rewardsTokenAddress);
        lastUpdateTime = block.timestamp;
    }

    // --- External Functions | Staking Logic ---

    /**
     * @notice Stakes multiple NFTs for the message sender.
     * @dev The caller must approve the contract to manage their NFTs beforehand.
     * @param _tokenIds An array of NFT token IDs to stake.
     */
    function stake(uint256[] calldata _tokenIds) external nonReentrant updateReward(msg.sender) {
        uint256 numTokens = _tokenIds.length;
        if (numTokens == 0) revert("Staking: No token IDs provided");

        for (uint256 i = 0; i < numTokens; i++) {
            uint256 tokenId = _tokenIds[i];
            if (nftCollection.ownerOf(tokenId) != msg.sender) {
                revert("Staking: You do not own this NFT");
            }
            if (stakerOf[tokenId] != address(0)) {
                revert("Staking: Token is already staked");
            }

            nftCollection.transferFrom(msg.sender, address(this), tokenId);
            stakedTokens[msg.sender].add(tokenId);
            stakerOf[tokenId] = msg.sender;
            emit Staked(msg.sender, tokenId);
        }

        stakers[msg.sender].amountStaked += numTokens;
        totalStaked += numTokens;
    }

    /**
     * @notice Unstakes multiple NFTs for the message sender.
     * @param _tokenIds An array of NFT token IDs to unstake.
     */
    function unstake(uint256[] calldata _tokenIds) external nonReentrant updateReward(msg.sender) {
        uint256 numTokens = _tokenIds.length;
        if (numTokens == 0) revert("Staking: No token IDs provided");

        for (uint256 i = 0; i < numTokens; i++) {
            uint256 tokenId = _tokenIds[i];
            if (stakerOf[tokenId] != msg.sender) {
                revert("Staking: You did not stake this token");
            }

            stakedTokens[msg.sender].remove(tokenId);
            stakerOf[tokenId] = address(0);
            nftCollection.transferFrom(address(this), msg.sender, tokenId);
            emit Unstaked(msg.sender, tokenId);
        }

        stakers[msg.sender].amountStaked -= numTokens;
        totalStaked -= numTokens;
    }

    /**
     * @notice Claims all available rewards for the message sender.
     */
    function claimRewards() external nonReentrant updateReward(msg.sender) {
        uint256 reward = stakers[msg.sender].rewards;
        if (reward == 0) revert("Staking: No rewards to claim");

        stakers[msg.sender].rewards = 0;
        totalRewardsPaidOut += reward;
        rewardsToken.transfer(msg.sender, reward);
        emit RewardsClaimed(msg.sender, reward);
    }

    // --- View Functions | UI Support ---

    /**
     * @notice Calculates the total rewards accumulated per token since the last update.
     * @return The amount of rewards per token.
     */
    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored + (((block.timestamp - lastUpdateTime) * rewardRate * 1e18) / totalStaked);
    }

    /**
     * @notice Calculates the pending rewards for a specific user.
     * @param _user The address of the user.
     * @return The total rewards earned but not yet claimed.
     */
    function earned(address _user) public view returns (uint256) {
        uint256 userStakedCount = stakers[_user].amountStaked;
        if (userStakedCount == 0) {
            return stakers[_user].rewards;
        }
        return
            ((userStakedCount * (rewardPerToken() - stakers[_user].rewardPerTokenPaid)) / 1e18) + stakers[_user].rewards;
    }

    /**
     * @notice Gets the number of NFTs a user has staked.
     * @param _user The address of the staker.
     * @return The count of staked NFTs.
     */
    function stakedBalanceOf(address _user) external view returns (uint256) {
        return stakers[_user].amountStaked;
    }

    /**
     * @notice Gets the list of token IDs staked by a user.
     * @param _user The address of the staker.
     * @return An array of token IDs.
     */
    function getStakedTokens(address _user) external view returns (uint256[] memory) {
        return stakedTokens[_user].values();
    }

    // --- Owner Functions ---

    /**
     * @notice Sets the rate at which rewards are distributed.
     * @dev This can be used to adjust the APY for stakers.
     * @param _newRate The new reward rate in tokens per second.
     */
    function setRewardRate(uint256 _newRate) external onlyOwner {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;
        rewardRate = _newRate;
        emit RewardRateUpdated(_newRate);
    }

    /**
     * @notice In case rewards tokens get stuck in the contract, the owner can recover them.
     * @dev It's recommended to only recover tokens that are not the designated rewards token.
     * @param _tokenAddress The address of the ERC20 token to recover.
     * @param _amount The amount of tokens to recover.
     */
    function recoverERC20(address _tokenAddress, uint256 _amount) external onlyOwner {
        IERC20(_tokenAddress).transfer(owner(), _amount);
    }
}
