// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title NFTStaking
 * @author Your Name
 * @notice A contract for staking NFTs to earn ERC20 token rewards.
 * @dev This contract allows users to stake NFTs from a specific collection and earn rewards
 * based on a predetermined rate. The reward calculation is based on the Synthetix
 * StakingRewards contract model.
 */
contract NFTStaking is ReentrancyGuard, Ownable {
    // --- Interfaces ---

    /// @notice The NFT collection that can be staked.
    IERC721 public immutable nftCollection;
    /// @notice The token given as a reward for staking.
    IERC20 public immutable rewardToken;

    // --- State Variables ---

    /**
     * @notice The rate at which rewards are distributed per second (in wei).
     * @dev Example: 100 tokens with 18 decimals per day would be: (100 * 10**18) / 86400.
     */
    uint256 public rewardRate;

    /// @notice The last time reward states were updated.
    uint256 public lastUpdateTime;

    /// @notice The cumulative reward per token, scaled by 1e18.
    uint256 public rewardPerTokenStored;

    /// @notice The total number of NFTs currently staked in the contract.
    uint256 public totalSupply;

    // --- Mappings ---

    /// @notice Stores the reward-per-token-paid for each user, scaled by 1e18.
    mapping(address => uint256) public userRewardPerTokenPaid;

    /// @notice Stores the accumulated rewards for each user that are yet to be claimed.
    mapping(address => uint256) public rewards;

    /// @notice Maps a staked token ID to the address of its owner.
    mapping(uint256 => address) public stakedTokens;

    /**
     * @notice Maps a user address to the list of token IDs they have staked.
     * @dev Be cautious with this mapping as it can be gas-intensive to manage if a user stakes many NFTs.
     */
    mapping(address => uint256[]) public userStakedTokens;

    /// @notice Maps a user address to the number of NFTs they have staked.
    mapping(address => uint256) public userStakedBalances;

    // --- Events ---

    /// @notice Emitted when a user stakes an NFT.
    event Staked(address indexed user, uint256 indexed tokenId);

    /// @notice Emitted when a user withdraws a staked NFT.
    event Withdrawn(address indexed user, uint256 indexed tokenId);

    /// @notice Emitted when a user claims their earned rewards.
    event RewardClaimed(address indexed user, uint256 amount);

    // --- Constructor ---

    /**
     * @notice Initializes the staking contract.
     * @param _nftCollection The address of the NFT (ERC721) contract.
     * @param _rewardToken The address of the reward token (ERC20) contract.
     */
    constructor(address _nftCollection, address _rewardToken) {
        if (_nftCollection == address(0)) revert("NFTStaking: NFT collection address cannot be zero");
        if (_rewardToken == address(0)) revert("NFTStaking: Reward token address cannot be zero");

        nftCollection = IERC721(_nftCollection);
        rewardToken = IERC20(_rewardToken);

        lastUpdateTime = block.timestamp;

        // Set an initial reward rate of 100 tokens (assuming 18 decimals) per day.
        // This can be updated by the owner later via a dedicated function.
        // 100 * 10^18 / (seconds in a day)
        rewardRate = (100 * 1e18) / 1 days;
    }

    // --- Modifiers ---

    /**
     * @notice Updates the reward state for a specific user.
     * @dev This modifier should be applied to functions that change a user's staked balance
     * (e.g., stake, withdraw, claim).
     * It ensures that rewards are calculated correctly before the user's state changes.
     */
    modifier updateReward(address _user) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;
        rewards[_user] = earned(_user);
        userRewardPerTokenPaid[_user] = rewardPerTokenStored;
        _;
    }

    // --- View Functions ---

    /**
     * @notice Calculates the reward per token accumulated since the last update.
     * @return The updated reward per token value, scaled by 1e18.
     */
    function rewardPerToken() public view returns (uint256) {
        if (totalSupply == 0) {
            return rewardPerTokenStored;
        }
        uint256 timeElapsed = block.timestamp - lastUpdateTime;
        // rewardPerTokenIncrement is scaled by 1e18
        uint256 rewardPerTokenIncrement = (timeElapsed * rewardRate * 1e18) / totalSupply;
        return rewardPerTokenStored + rewardPerTokenIncrement;
    }

    /**
     * @notice Calculates the total unclaimed rewards for a specific user.
     * @param _user The address of the user.
     * @return The amount of rewards the user has earned but not yet claimed.
     */
    function earned(address _user) public view returns (uint256) {
        uint256 userBalance = userStakedBalances[_user];
        // The expression `rewardPerToken() - userRewardPerTokenPaid[_user]` is scaled by 1e18.
        // Multiplying by userBalance gives a result scaled by 1e18.
        // We divide by 1e18 to get back to the token's decimal base.
        return ((userBalance * (rewardPerToken() - userRewardPerTokenPaid[_user])) / 1e18) + rewards[_user];
    }
}
