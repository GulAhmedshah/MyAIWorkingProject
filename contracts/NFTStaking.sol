// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Receiver.sol";

/**
 * @title NFTStaking
 * @author Your Name
 * @notice A contract for staking ERC721 NFTs to earn ERC20 token rewards.
 * @dev This contract allows users to stake NFTs from a specific collection and earn rewards over time.
 * It includes emergency functions, pausable state, and owner-only administrative functions.
 */
contract NFTStaking is Ownable, ReentrancyGuard, Pausable, IERC721Receiver {
    using SafeERC20 for IERC20;

    /* =============================================================
                               STATE VARIABLES
    ============================================================== */

    /// @notice The ERC20 token used for rewards.
    IERC20 public immutable rewardsToken;
    /// @notice The ERC721 NFT collection that can be staked.
    IERC721 public immutable nftCollection;

    /// @notice The amount of reward tokens earned per second per staked NFT.
    uint256 public rewardRate;
    /// @notice The last timestamp when global rewards were updated.
    uint256 public lastUpdateTime;
    /// @notice The accumulated rewards per token, scaled by 1e18 for precision.
    uint256 public rewardPerTokenStored;

    /// @notice Mapping from user address to their earned but unclaimed rewards.
    mapping(address => uint256) public rewards;
    /// @notice Mapping from user to their last paid out reward-per-token value.
    mapping(address => uint256) public userRewardPerTokenPaid;
    /// @notice Mapping from tokenId to the staker's address.
    mapping(uint256 => address) public stakedTokens;

    /// @notice A struct to store staking information for each user.
    struct Staker {
        uint256 amountStaked;
        uint256 timeOfLastUpdate;
    }

    /// @notice Mapping from user address to their staker information.
    mapping(address => Staker) public stakers;

    /* =============================================================
                                   EVENTS
    ============================================================== */

    /// @notice Emitted when a user stakes one or more NFTs.
    event Staked(address indexed user, uint256[] tokenIds);
    /// @notice Emitted when a user withdraws one or more NFTs.
    event Withdrawn(address indexed user, uint256[] tokenIds);
    /// @notice Emitted when a user claims their earned rewards.
    event RewardsClaimed(address indexed user, uint256 amount);
    /// @notice Emitted when the owner updates the reward rate.
    event RewardRateUpdated(uint256 newRate);

    /* =============================================================
                                 MODIFIERS
    ============================================================== */

    /**
     * @dev Modifier to update a user's reward entitlement before a state change.
     * @param _account The address of the user whose rewards need to be updated.
     */
    modifier updateReward(address _account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;
        rewards[_account] = earned(_account);
        userRewardPerTokenPaid[_account] = rewardPerTokenStored;
        stakers[_account].timeOfLastUpdate = block.timestamp;
        _;
    }

    /* =============================================================
                               CONSTRUCTOR
    ============================================================== */

    /**
     * @notice Initializes the staking contract.
     * @param _rewardsToken The address of the ERC20 rewards token.
     * @param _nftCollection The address of the ERC721 NFT collection.
     * @param _rewardRate The initial reward rate per second per NFT.
     */
    constructor(address _rewardsToken, address _nftCollection, uint256 _rewardRate) {
        require(_rewardsToken != address(0), "NFTStaking: Invalid rewards token address");
        require(_nftCollection != address(0), "NFTStaking: Invalid NFT collection address");
        require(_rewardRate > 0, "NFTStaking: Reward rate must be positive");

        rewardsToken = IERC20(_rewardsToken);
        nftCollection = IERC721(_nftCollection);
        rewardRate = _rewardRate;
        lastUpdateTime = block.timestamp;
    }

    /* =============================================================
                               CORE LOGIC
    ============================================================== */

    /**
     * @notice Stakes multiple NFTs.
     * @dev The caller must approve the contract to transfer the NFTs first.
     * @param tokenIds An array of token IDs to stake.
     */
    function stake(uint256[] calldata tokenIds) external nonReentrant whenNotPaused updateReward(msg.sender) {
        uint256 numTokens = tokenIds.length;
        require(numTokens > 0, "NFTStaking: No token IDs provided");

        Staker storage staker = stakers[msg.sender];
        staker.amountStaked += numTokens;

        for (uint256 i = 0; i < numTokens; i++) {
            uint256 tokenId = tokenIds[i];
            require(nftCollection.ownerOf(tokenId) == msg.sender, "NFTStaking: Not the owner of the token");
            require(stakedTokens[tokenId] == address(0), "NFTStaking: Token already staked");

            stakedTokens[tokenId] = msg.sender;
            nftCollection.safeTransferFrom(msg.sender, address(this), tokenId);
        }

        emit Staked(msg.sender, tokenIds);
    }

    /**
     * @notice Withdraws multiple staked NFTs and claims pending rewards.
     * @param tokenIds An array of token IDs to withdraw.
     */
    function withdraw(uint256[] calldata tokenIds) external nonReentrant whenNotPaused updateReward(msg.sender) {
        uint256 numTokens = tokenIds.length;
        require(numTokens > 0, "NFTStaking: No token IDs provided");

        Staker storage staker = stakers[msg.sender];
        require(staker.amountStaked >= numTokens, "NFTStaking: Attempting to withdraw more than staked");

        staker.amountStaked -= numTokens;

        _claimRewards(msg.sender);

        for (uint256 i = 0; i < numTokens; i++) {
            uint256 tokenId = tokenIds[i];
            require(stakedTokens[tokenId] == msg.sender, "NFTStaking: Not the owner of the token");

            delete stakedTokens[tokenId];
            nftCollection.safeTransferFrom(address(this), msg.sender, tokenId);
        }

        emit Withdrawn(msg.sender, tokenIds);
    }

    /**
     * @notice Claims all pending rewards for the message sender.
     */
    function claimRewards() external nonReentrant whenNotPaused updateReward(msg.sender) {
        _claimRewards(msg.sender);
    }

    /**
     * @notice Withdraws staked NFTs without claiming rewards in an emergency.
     * @dev This function bypasses reward calculations and the paused state.
     * @param tokenIds The list of token IDs to withdraw.
     */
    function emergencyWithdraw(uint256[] calldata tokenIds) external nonReentrant {
        uint256 numTokens = tokenIds.length;
        require(numTokens > 0, "NFTStaking: No token IDs provided");

        Staker storage staker = stakers[msg.sender];
        require(staker.amountStaked >= numTokens, "NFTStaking: Attempting to withdraw more than staked");

        staker.amountStaked -= numTokens;

        for (uint256 i = 0; i < numTokens; i++) {
            uint256 tokenId = tokenIds[i];
            require(stakedTokens[tokenId] == msg.sender, "NFTStaking: Not the owner of the token");

            delete stakedTokens[tokenId];
            nftCollection.safeTransferFrom(address(this), msg.sender, tokenId);
        }

        emit Withdrawn(msg.sender, tokenIds);
    }

    /* =============================================================
                               ADMIN FUNCTIONS
    ============================================================== */

    /**
     * @notice Sets a new reward rate.
     * @dev Updates accumulated rewards with the old rate before changing it.
     * @param _newRate The new reward rate per second per NFT.
     */
    function setRewardRate(uint256 _newRate) external onlyOwner {
        require(_newRate > 0, "NFTStaking: Rate must be greater than 0");
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;
        rewardRate = _newRate;
        emit RewardRateUpdated(_newRate);
    }

    /**
     * @notice Pauses the contract, halting stake, withdraw, and claimRewards.
     * @dev Can only be called by the owner. Emits a {Paused} event.
     * Emergency functions will still be available.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses the contract, resuming normal operations.
     * @dev Can only be called by the owner. Emits an {Unpaused} event.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /* =============================================================
                               VIEW FUNCTIONS
    ============================================================== */

    /**
     * @notice Calculates the total rewards earned by a user.
     * @param _account The address of the user.
     * @return The total rewards earned.
     */
    function earned(address _account) public view returns (uint256) {
        Staker memory staker = stakers[_account];
        return
            ((staker.amountStaked * (rewardPerToken() - userRewardPerTokenPaid[_account])) / 1e18) +
            rewards[_account];
    }

    /**
     * @notice Calculates the reward per token since the last global update.
     * @return The reward per token, scaled by 1e18.
     */
    function rewardPerToken() public view returns (uint256) {
        uint256 totalStaked = nftCollection.balanceOf(address(this));
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored + (((block.timestamp - lastUpdateTime) * rewardRate * 1e18) / totalStaked);
    }

    /* =============================================================
                              INTERNAL FUNCTIONS
    ============================================================== */

    /**
     * @dev Internal function to handle the reward claiming logic.
     * @param _account The account to claim rewards for.
     */
    function _claimRewards(address _account) internal {
        uint256 rewardAmount = rewards[_account];
        if (rewardAmount > 0) {
            rewards[_account] = 0;
            rewardsToken.safeTransfer(_account, rewardAmount);
            emit RewardsClaimed(_account, rewardAmount);
        }
    }

    /**
     * @dev See {IERC721Receiver-onERC721Received}.
     *      This contract is not designed to receive NFTs via direct transfer.
     *      Always use the `stake` function.
     */
    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
