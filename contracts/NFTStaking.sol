// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title NFTStaking
 * @author Your Name
 * @notice A contract for staking ERC721 NFTs to earn ERC20 token rewards.
 * @dev This contract implements reentrancy guards, uses SafeERC20 for transfers,
 * and includes comprehensive validation and event emissions for security and transparency.
 * The reward calculation logic is based on the Synthetix StakingRewards model.
 */
contract NFTStaking is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    // Staking and Rewards Tokens
    IERC721 public immutable nftCollection;
    IERC20 public immutable rewardsToken;

    // Staking Data
    // Mapping from tokenId to the address of the staker.
    mapping(uint256 => address) public stakerOf;
    // Mapping from a staker's address to an array of their staked tokenIds.
    mapping(address => uint256[]) private stakedTokens;
    // Mapping from a tokenId to its index in the staker's stakedTokens array.
    // This is used for efficient O(1) removal.
    mapping(uint256 => uint256) private stakedTokenIndex;
    // Total number of NFTs currently staked in the contract.
    uint256 public totalStaked;

    // Reward Calculation Data
    // Mapping from user address to their accumulated but unclaimed rewards.
    mapping(address => uint256) public rewards;
    // The rate of reward distribution per second.
    uint256 public rewardRate;
    // The timestamp when the current reward period ends.
    uint256 public periodFinish;
    // The last time rewards were updated for any user.
    uint256 public lastUpdateTime;
    // The cumulative reward per staked token since the beginning.
    uint256 public rewardPerTokenStored;
    // Mapping to track the rewardPerTokenStored value for each user's last update.
    mapping(address => uint256) public userRewardPerTokenPaid;


    /* ========== EVENTS ========== */

    event Staked(address indexed user, uint256 indexed tokenId);
    event Unstaked(address indexed user, uint256 indexed tokenId);
    event RewardsClaimed(address indexed user, uint256 amount);
    event RewardRateSet(uint256 newRate);
    event RewardPeriodFinishSet(uint256 newPeriodFinish);
    event RewardsNotified(uint256 amount);


    /* ========== MODIFIERS ========== */

    /**
     * @dev Modifier to check if the given token ID exists in the NFT collection.
     * @notice This check is implicitly performed by calling `nftCollection.ownerOf()`,
     * which reverts if the token does not exist.
     * @param tokenId The ID of the token to check.
     */
    modifier validToken(uint256 tokenId) {
        // This will revert if the token does not exist, effectively checking its existence.
        nftCollection.ownerOf(tokenId);
        _;
    }


    /* ========== CONSTRUCTOR ========== */

    /**
     * @dev Initializes the contract with the NFT and rewards token addresses.
     * @param _nftCollectionAddress The address of the ERC721 NFT collection contract.
     * @param _rewardsTokenAddress The address of the ERC20 rewards token contract.
     */
    constructor(address _nftCollectionAddress, address _rewardsTokenAddress) {
        if (_nftCollectionAddress == address(0)) {
            revert("NFTStaking: NFT collection address cannot be zero");
        }
        if (_rewardsTokenAddress == address(0)) {
            revert("NFTStaking: Rewards token address cannot be zero");
        }

        nftCollection = IERC721(_nftCollectionAddress);
        rewardsToken = IERC20(_rewardsTokenAddress);
    }


    /* ========== EXTERNAL VIEWS ========== */

    /**
     * @dev Returns the list of token IDs staked by a specific user.
     * @param _user The address of the user.
     * @return An array of token IDs.
     */
    function getStakedTokens(address _user) external view returns (uint256[] memory) {
        return stakedTokens[_user];
    }

    /**
     * @dev Calculates the amount of rewards a user has earned but not yet claimed.
     * @param _account The address of the user.
     * @return The total rewards earned.
     */
    function earned(address _account) public view returns (uint256) {
        uint256 userStakedCount = stakedTokens[_account].length;
        if (userStakedCount == 0) {
            return rewards[_account];
        }
        return
            (userStakedCount * (rewardPerToken() - userRewardPerTokenPaid[_account])) / 1e18 +
            rewards[_account];
    }


    /* ========== EXTERNAL FUNCTIONS (Staking & Unstaking) ========== */

    /**
     * @dev Stakes one or more NFTs.
     * @notice The caller must approve the contract to transfer the NFTs.
     * @param _tokenIds An array of token IDs to stake.
     */
    function stake(uint256[] calldata _tokenIds) external nonReentrant updateReward(msg.sender) {
        if (_tokenIds.length == 0) {
            revert("NFTStaking: Cannot stake zero tokens");
        }

        for (uint256 i = 0; i < _tokenIds.length; ++i) {
            uint256 tokenId = _tokenIds[i];

            if (nftCollection.ownerOf(tokenId) != msg.sender) {
                revert("NFTStaking: Caller is not the owner of the NFT");
            }
            if (stakerOf[tokenId] != address(0)) {
                revert("NFTStaking: Token is already staked");
            }

            // Add token to user's staked list
            stakedTokens[msg.sender].push(tokenId);
            stakedTokenIndex[tokenId] = stakedTokens[msg.sender].length - 1;
            stakerOf[tokenId] = msg.sender;

            emit Staked(msg.sender, tokenId);

            // Transfer NFT to the contract
            nftCollection.safeTransferFrom(msg.sender, address(this), tokenId);
        }
        totalStaked += _tokenIds.length;
    }

    /**
     * @dev Unstakes one or more NFTs.
     * @param _tokenIds An array of token IDs to unstake.
     */
    function unstake(uint256[] calldata _tokenIds) external nonReentrant updateReward(msg.sender) {
        if (_tokenIds.length == 0) {
            revert("NFTStaking: Cannot unstake zero tokens");
        }

        for (uint256 i = 0; i < _tokenIds.length; ++i) {
            uint256 tokenId = _tokenIds[i];

            if (stakerOf[tokenId] != msg.sender) {
                revert("NFTStaking: Caller is not the staker of the NFT");
            }

            // Efficiently remove token from user's staked list
            _removeTokenFromStaker(msg.sender, tokenId);
            delete stakerOf[tokenId];
            delete stakedTokenIndex[tokenId];

            emit Unstaked(msg.sender, tokenId);
            
            // Transfer NFT back to the staker
            nftCollection.safeTransferFrom(address(this), msg.sender, tokenId);
        }
        totalStaked -= _tokenIds.length;
    }

    /* ========== EXTERNAL FUNCTIONS (Rewards) ========== */

    /**
     * @dev Claims all available rewards for the message sender.
     */
    function claimRewards() external nonReentrant updateReward(msg.sender) {
        uint256 rewardAmount = rewards[msg.sender];
        if (rewardAmount == 0) {
            revert("NFTStaking: No rewards to claim");
        }

        rewards[msg.sender] = 0;
        rewardsToken.safeTransfer(msg.sender, rewardAmount);

        emit RewardsClaimed(msg.sender, rewardAmount);
    }

    /* ========== RESTRICTED FUNCTIONS (Owner) ========== */

    /**
     * @dev Funds the contract with reward tokens and sets the reward rate over a duration.
     * @notice The contract must be approved to spend the owner's reward tokens.
     * @notice This will start a new reward distribution period.
     * @param _amount The total amount of reward tokens to distribute.
     * @param _duration The duration over which to distribute the rewards, in seconds.
     */
    function notifyRewardAmount(uint256 _amount, uint256 _duration) external onlyOwner nonReentrant updateReward(address(0)) {
        if (_amount == 0) {
            revert("NFTStaking: Amount must be greater than zero");
        }
        if (_duration == 0) {
            revert("NFTStaking: Duration must be greater than zero");
        }

        if (block.timestamp >= periodFinish) {
            rewardRate = _amount / _duration;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (_amount + leftover) / _duration;
        }

        if (rewardRate == 0) {
            revert("NFTStaking: Reward rate cannot be zero, check amount and duration");
        }

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + _duration;

        // Transfer new rewards into the contract
        rewardsToken.safeTransferFrom(msg.sender, address(this), _amount);

        emit RewardsNotified(_amount);
        emit RewardRateSet(rewardRate);
        emit RewardPeriodFinishSet(periodFinish);
    }


    /* ========== INTERNAL & PRIVATE FUNCTIONS ========== */

    /**
     * @dev Modifier that updates the reward state for a given account.
     * @param _account The account to update rewards for. `address(0)` updates global state only.
     */
    modifier updateReward(address _account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (_account != address(0)) {
            rewards[_account] = earned(_account);
            userRewardPerTokenPaid[_account] = rewardPerTokenStored;
        }
        _;
    }

    /**
     * @dev Calculates the cumulative reward per token since the last update.
     * @return The reward per token value, scaled by 1e18.
     */
    function rewardPerToken() internal view returns (uint256) {
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored +
            (((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18) / totalStaked);
    }

    /**
     * @dev Gets the timestamp for the last moment rewards are applicable.
     * @return The minimum of the current block timestamp and the period finish time.
     */
    function lastTimeRewardApplicable() internal view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    /**
     * @dev Private function to remove a token from a staker's list efficiently.
     * @notice Uses the "swap and pop" method for O(1) removal.
     * @param _staker The address of the staker.
     * @param _tokenId The ID of the token to remove.
     */
    function _removeTokenFromStaker(address _staker, uint256 _tokenId) private {
        uint256[] storage tokens = stakedTokens[_staker];
        uint256 index = stakedTokenIndex[_tokenId];
        uint256 lastTokenId = tokens[tokens.length - 1];

        // Move the last token to the position of the token being removed
        tokens[index] = lastTokenId;
        stakedTokenIndex[lastTokenId] = index;

        // Remove the last element
        tokens.pop();
    }
}
