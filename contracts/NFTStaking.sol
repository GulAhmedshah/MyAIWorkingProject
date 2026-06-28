// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/**
 * @title NFTStaking
 * @author Your Name
 * @notice A contract for staking NFTs to earn ERC20 rewards.
 * @dev This contract allows users to stake ERC721 tokens and earn rewards based on the staking duration.
 */
contract NFTStaking is ReentrancyGuard, ERC721Holder {
    using SafeMath for uint256;

    // --- State Variables ---

    // The NFT contract being staked
    IERC721 public immutable nft;
    // The ERC20 token used for rewards
    IERC20 public immutable rewardToken;

    // Reward rate per NFT, per hour
    uint256 public rewardsPerHour;

    // Total number of NFTs currently staked in the contract
    uint256 public totalSupply;

    // Mapping from user address to their staked balance (number of NFTs)
    mapping(address => uint256) public userStakedBalances;

    // Information about each staked token
    struct StakerInfo {
        address owner;      // The address of the staker
        uint256 timestamp;  // The timestamp when the token was staked or rewards last updated
        bool isStaked;      // Staking status
    }

    // Mapping from tokenId to staker info
    mapping(uint256 => StakerInfo) public stakedTokens;

    // Mapping from user address to an array of their staked tokenIds. Private to control access.
    mapping(address => uint256[]) private userStakedTokens;

    // Mapping from user address to their accumulated (but not yet claimed) rewards
    mapping(address => uint256) public rewards;

    // --- Events ---

    /**
     * @notice Emitted when one or more NFTs are staked.
     * @param owner The address of the staker.
     * @param tokenId The ID of the token that was staked.
     * @param timestamp The time the token was staked.
     */
    event Staked(address indexed owner, uint256 indexed tokenId, uint256 timestamp);

    /**
     * @notice Emitted when a user unstakes an NFT.
     * @param owner The address of the staker.
     * @param tokenId The ID of the token that was unstaked.
     */
    event Unstaked(address indexed owner, uint256 indexed tokenId);

    /**
     * @notice Emitted when a user claims their rewards.
     * @param user The address of the user.
     * @param reward The amount of reward tokens claimed.
     */
    event RewardPaid(address indexed user, uint256 reward);


    // --- Constructor ---

    /**
     * @notice Initializes the staking contract.
     * @param _nftAddress The address of the ERC721 token contract.
     * @param _rewardTokenAddress The address of the ERC20 reward token contract.
     * @param _rewardsPerHour The number of reward tokens earned per hour for each staked NFT.
     */
    constructor(address _nftAddress, address _rewardTokenAddress, uint256 _rewardsPerHour) {
        require(_nftAddress != address(0), "NFTStaking: NFT address cannot be zero");
        require(_rewardTokenAddress != address(0), "NFTStaking: Reward token address cannot be zero");

        nft = IERC721(_nftAddress);
        rewardToken = IERC20(_rewardTokenAddress);
        rewardsPerHour = _rewardsPerHour;
    }


    // --- Modifiers ---

    /**
     * @dev Modifier to update a user's reward balance before a state change.
     * It calculates pending rewards, adds them to the user's total,
     * and resets the timestamp for all of the user's staked tokens to prevent double-counting.
     * @param _user The address of the user whose rewards are being updated.
     */
    modifier updateReward(address _user) {
        if (userStakedBalances[_user] > 0) {
            uint256 pendingRewards = calculateRewards(_user);
            rewards[_user] = rewards[_user].add(pendingRewards);

            // Reset the timestamp for each of the user's staked tokens
            uint256[] storage staked = userStakedTokens[_user];
            for (uint256 i = 0; i < staked.length; i++) {
                stakedTokens[staked[i]].timestamp = block.timestamp;
            }
        }
        _;
    }


    // --- Reward Calculation ---

    /**
     * @notice Calculates the pending rewards for a specific user.
     * @dev This is a view function that does not alter state.
     * @param _user The address of the user.
     * @return The total pending rewards in reward token units.
     */
    function calculateRewards(address _user) public view returns (uint256) {
        uint256 totalPendingRewards = 0;
        uint256[] memory userTokens = userStakedTokens[_user];

        for (uint256 i = 0; i < userTokens.length; i++) {
            StakerInfo memory info = stakedTokens[userTokens[i]];
            uint256 timeElapsed = block.timestamp.sub(info.timestamp);
            // rewards = (timeElapsed * rewardsPerHour) / 3600
            totalPendingRewards = totalPendingRewards.add(timeElapsed.mul(rewardsPerHour).div(3600));
        }

        return totalPendingRewards;
    }


    // --- Staking Logic ---

    /**
     * @notice Stakes one or more NFTs.
     * @dev The caller must be the owner of all NFTs and must have approved this contract.
     * The `updateReward` modifier is called first to ensure any existing staked tokens' rewards are up to date.
     * @param tokenIds An array of token IDs to be staked.
     */
    function stake(uint256[] calldata tokenIds) external nonReentrant updateReward(msg.sender) {
        require(tokenIds.length > 0, "NFTStaking: Cannot stake zero tokens");

        uint256 numTokensToStake = tokenIds.length;

        for (uint256 i = 0; i < numTokensToStake; i++) {
            uint256 tokenId = tokenIds[i];

            // 1. Check ownership
            require(nft.ownerOf(tokenId) == msg.sender, "NFTStaking: Caller is not the owner of the token");
            
            // 2. Check if token is already staked
            require(!stakedTokens[tokenId].isStaked, "NFTStaking: Token is already staked");

            // 3. Transfer NFT to this contract
            nft.safeTransferFrom(msg.sender, address(this), tokenId);

            // 4. Update staking info
            stakedTokens[tokenId] = StakerInfo({
                owner: msg.sender,
                timestamp: block.timestamp,
                isStaked: true
            });

            // 5. Add token to user's list of staked tokens
            userStakedTokens[msg.sender].push(tokenId);

            // 6. Emit event
            emit Staked(msg.sender, tokenId, block.timestamp);
        }

        // 7. Update user and global staking counts (done outside loop for gas efficiency)
        userStakedBalances[msg.sender] = userStakedBalances[msg.sender].add(numTokensToStake);
        totalSupply = totalSupply.add(numTokensToStake);
    }


    // --- View Functions ---

    /**
     * @notice Gets the list of token IDs staked by a specific user.
     * @param _user The address of the user.
     * @return An array of token IDs.
     */
    function getStakedTokens(address _user) external view returns (uint256[] memory) {
        return userStakedTokens[_user];
    }
}
