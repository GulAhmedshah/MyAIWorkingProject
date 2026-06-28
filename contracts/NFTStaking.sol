// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

/**
 * @title NFTStaking
 * @author Your Name
 * @notice A contract for staking NFTs to earn ERC20 rewards.
 * @dev This contract allows users to stake ERC721 tokens and earn ERC20 tokens
 *      based on the duration of the stake. It includes functionalities for
 *      staking, withdrawing, and claiming rewards.
 */
contract NFTStaking is ReentrancyGuard, ERC721Holder {
    // =============================================================
    //                           State Variables
    // =============================================================

    /// @notice The ERC721 token contract that can be staked.
    IERC721 public immutable nftCollection;

    /// @notice The ERC20 token contract used for rewards.
    IERC20 public immutable rewardsToken;

    /// @notice The amount of reward tokens earned per NFT per day.
    uint256 public constant REWARD_RATE = 10 * 1e18; // 10 tokens per day

    /// @notice The number of seconds in a day, for reward calculations.
    uint256 public constant SECONDS_IN_A_DAY = 86400;

    /// @notice The total number of NFTs currently staked in the contract.
    uint256 public totalSupply;

    /// @notice Mapping from a tokenId to the address of its staker.
    mapping(uint256 => address) public stakedTokens;

    /// @notice Mapping from a staker's address to their count of staked NFTs.
    mapping(address => uint256) public userStakedBalances;

    /// @notice Mapping from a staker's address to an array of their staked tokenIds.
    mapping(address => uint256[]) public userStakedTokens;

    /// @notice Mapping from a tokenId to the timestamp it was staked or last updated.
    mapping(uint256 => uint256) public tokenStakeTimestamps;

    /// @notice Mapping from a user's address to their claimable rewards balance.
    mapping(address => uint256) public userRewards;

    /// @dev Mapping from a tokenId to its index in the userStakedTokens array.
    ///      This is crucial for efficient removal (O(1)).
    mapping(uint256 => uint256) private _userStakedTokenIndex;

    // =============================================================
    //                              Events
    // =============================================================

    /**
     * @notice Emitted when one or more NFTs are staked.
     * @param staker The address of the user who staked the NFT.
     * @param tokenId The ID of the staked NFT.
     * @param timestamp The block timestamp when the staking occurred.
     */
    event Staked(address indexed staker, uint256 indexed tokenId, uint256 timestamp);

    /**
     * @notice Emitted when one or more NFTs are withdrawn.
     * @param staker The address of the user who withdrew the NFT.
     * @param tokenId The ID of the withdrawn NFT.
     * @param timestamp The block timestamp when the withdrawal occurred.
     */
    event Withdrawn(address indexed staker, uint256 indexed tokenId, uint256 timestamp);

    /**
     * @notice Emitted when a user claims their earned rewards.
     * @param staker The address of the user claiming rewards.
     * @param amount The amount of reward tokens claimed.
     */
    event RewardsClaimed(address indexed staker, uint256 amount);

    // =============================================================
    //                              Errors
    // =============================================================

    /// @notice The provided array of token IDs is empty.
    error EmptyArray();
    /// @notice The token is already staked.
    error AlreadyStaked();
    /// @notice The caller is not the staker of the token.
    error NotStaker();
    /// @notice The amount to withdraw exceeds the user's staked balance.
    error WithdrawAmountExceedsStakedAmount();
    /// @notice The user has no rewards to claim.
    error NoRewardsToClaim();

    // =============================================================
    //                             Modifiers
    // =============================================================

    /**
     * @notice A modifier that calculates and updates a user's rewards before a function executes.
     * @param _user The address of the user whose rewards are to be updated.
     */
    modifier updateReward(address _user) {
        _calculateRewards(_user);
        _;
    }

    // =============================================================
    //                           Constructor
    // =============================================================

    /**
     * @notice Initializes the staking contract with NFT and reward token addresses.
     * @param _nftCollectionAddress The address of the ERC721 NFT collection.
     * @param _rewardsTokenAddress The address of the ERC20 reward token.
     */
    constructor(address _nftCollectionAddress, address _rewardsTokenAddress) {
        if (_nftCollectionAddress == address(0) || _rewardsTokenAddress == address(0)) {
            revert("Zero address provided"); // Using require for constructor simplicity
        }
        nftCollection = IERC721(_nftCollectionAddress);
        rewardsToken = IERC20(_rewardsTokenAddress);
    }

    // =============================================================
    //                       External Functions
    // =============================================================

    /**
     * @notice Stakes multiple NFTs.
     * @dev The caller must be the owner of the NFTs and must have approved this contract.
     *         Rewards are updated before staking to correctly account for existing stakes.
     * @param _tokenIds An array of token IDs to be staked.
     */
    function stake(uint256[] calldata _tokenIds)
        external
        nonReentrant
        updateReward(msg.sender)
    {
        if (_tokenIds.length == 0) {
            revert EmptyArray();
        }

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 tokenId = _tokenIds[i];

            if (stakedTokens[tokenId] != address(0)) {
                revert AlreadyStaked();
            }

            nftCollection.safeTransferFrom(msg.sender, address(this), tokenId);

            stakedTokens[tokenId] = msg.sender;
            tokenStakeTimestamps[tokenId] = block.timestamp;
            totalSupply++;
            userStakedBalances[msg.sender]++;

            userStakedTokens[msg.sender].push(tokenId);
            _userStakedTokenIndex[tokenId] = userStakedTokens[msg.sender].length - 1;

            emit Staked(msg.sender, tokenId, block.timestamp);
        }
    }

    /**
     * @notice Withdraws multiple staked NFTs.
     * @dev The caller must be the original staker of the NFTs.
     *      Rewards are calculated and updated before withdrawal.
     * @param _tokenIds An array of token IDs to be withdrawn.
     */
    function withdraw(uint256[] calldata _tokenIds)
        external
        nonReentrant
        updateReward(msg.sender)
    {
        if (_tokenIds.length == 0) {
            revert EmptyArray();
        }

        uint256 userStakeCount = userStakedBalances[msg.sender];
        if (_tokenIds.length > userStakeCount) {
            revert WithdrawAmountExceedsStakedAmount();
        }

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 tokenId = _tokenIds[i];

            if (stakedTokens[tokenId] != msg.sender) {
                revert NotStaker();
            }

            stakedTokens[tokenId] = address(0);
            tokenStakeTimestamps[tokenId] = 0; 
            totalSupply--;
            userStakedBalances[msg.sender]--;

            // Efficiently remove token from userStakedTokens array using pop
            uint256 tokenIndex = _userStakedTokenIndex[tokenId];
            uint256[] storage stakedTokenIds = userStakedTokens[msg.sender];
            uint256 lastTokenId = stakedTokenIds[stakedTokenIds.length - 1];

            stakedTokenIds[tokenIndex] = lastTokenId;
            _userStakedTokenIndex[lastTokenId] = tokenIndex;

            stakedTokenIds.pop();
            delete _userStakedTokenIndex[tokenId];

            nftCollection.safeTransferFrom(address(this), msg.sender, tokenId);

            emit Withdrawn(msg.sender, tokenId, block.timestamp);
        }
    }

    /**
     * @notice Claims all available rewards for the caller.
     * @dev Rewards are updated before claiming. The contract must have sufficient
     *      reward tokens to fulfill the claim.
     */
    function claimRewards() external nonReentrant updateReward(msg.sender) {
        uint256 rewards = userRewards[msg.sender];
        if (rewards == 0) {
            revert NoRewardsToClaim();
        }

        userRewards[msg.sender] = 0;
        emit RewardsClaimed(msg.sender, rewards);

        if (rewardsToken.balanceOf(address(this)) < rewards) {
            userRewards[msg.sender] = rewards;
            revert("Insufficient reward token balance in contract");
        }

        rewardsToken.transfer(msg.sender, rewards);
    }

    // =============================================================
    //                        View Functions
    // =============================================================

    /**
     * @notice Calculates the pending rewards for a user without updating state.
     * @param _user The address of the user.
     * @return pendingRewards The total pending rewards for the user.
     */
    function getRewards(address _user) external view returns (uint256 pendingRewards) {
        pendingRewards = userRewards[_user];
        uint256[] memory stakedTokenIds = userStakedTokens[_user];

        for (uint256 i = 0; i < stakedTokenIds.length; i++) {
            uint256 tokenId = stakedTokenIds[i];
            uint256 lastUpdate = tokenStakeTimestamps[tokenId];
            if (lastUpdate > 0) {
                uint256 timeStaked = block.timestamp - lastUpdate;
                pendingRewards += (timeStaked * REWARD_RATE) / SECONDS_IN_A_DAY;
            }
        }
    }

    // =============================================================
    //                       Internal Functions
    // =============================================================

    /**
     * @notice Calculates and updates the rewards for all of a user's staked tokens.
     * @dev Iterates through all staked tokens of a user, calculates rewards accrued
     *      since the last update, adds them to `userRewards`, and resets the
     *      `tokenStakeTimestamps` to the current block timestamp for future calculations.
     * @param _user The address of the user.
     */
    function _calculateRewards(address _user) internal {
        uint256[] memory stakedTokenIds = userStakedTokens[_user];
        for (uint256 i = 0; i < stakedTokenIds.length; i++) {
            uint256 tokenId = stakedTokenIds[i];
            uint256 lastUpdate = tokenStakeTimestamps[tokenId];

            if (lastUpdate > 0) {
                uint256 timeStaked = block.timestamp - lastUpdate;
                uint256 rewards = (timeStaked * REWARD_RATE) / SECONDS_IN_A_DAY;
                userRewards[_user] += rewards;
                
                tokenStakeTimestamps[tokenId] = block.timestamp;
            }
        }
    }
}