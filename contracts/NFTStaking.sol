// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

/**
 * @title NFTStaking
 * @author Your Name
 * @notice A contract for staking NFTs (ERC721) to earn ERC20 token rewards.
 * @dev This contract allows users to stake their NFTs and claim rewards based on the staking duration.
 * It uses a reward-per-token model for fair reward distribution.
 */
contract NFTStaking is ReentrancyGuard, ERC721Holder {
    using SafeERC20 for IERC20;

    // --- State Variables ---

    /// @notice The ERC721 NFT collection that can be staked.
    IERC721 public immutable nftCollection;

    /// @notice The ERC20 token used for rewards.
    IERC20 public immutable rewardToken;

    /// @notice The amount of reward tokens distributed per second for the entire pool.
    uint256 public rewardRate;

    /// @notice The total number of NFTs currently staked in the contract.
    uint256 public totalStaked;

    /// @notice The timestamp of the last global reward calculation.
    uint256 public lastUpdateTime;

    /// @notice The accumulated rewards per token since the beginning, scaled by 1e18 for precision.
    uint256 public rewardPerTokenStored;

    // --- Mappings ---

    /// @notice Maps a user's address to their total claimable rewards.
    mapping(address => uint256) public rewards;

    /// @notice Maps a user's address to the `rewardPerTokenStored` value at their last interaction.
    mapping(address => uint256) public userRewardPerTokenPaid;

    /// @notice Maps a user's address to an array of their staked token IDs.
    mapping(address => uint256[]) private _stakedTokens;

    /// @notice Maps a token ID to the address of its staker.
    mapping(uint256 => address) public stakerOf;

    // --- Events ---

    /// @notice Emitted when one or more NFTs are staked.
    event Staked(address indexed owner, uint256[] tokenIds);

    /// @notice Emitted when one or more NFTs are unstaked.
    event Unstaked(address indexed owner, uint256[] tokenIds);

    /// @notice Emitted when a user claims their rewards.
    event RewardClaimed(address indexed user, uint256 amount);

    // --- Errors ---

    /// @notice Error thrown when an array of token IDs is empty.
    error EmptyTokenArray();

    /// @notice Error thrown when a user tries to stake a token they do not own or is not approved.
    error NotTokenOwnerOrApproved(uint256 tokenId);

    /// @notice Error thrown when a user tries to unstake a token that is not staked by them.
    error NotStaker(uint256 tokenId);

    /// @notice Error thrown when a user tries to claim zero rewards.
    error NoRewardsToClaim();

    // --- Constructor ---

    /**
     * @notice Initializes the staking contract.
     * @param _nftCollectionAddress The address of the ERC721 NFT contract.
     * @param _rewardTokenAddress The address of the ERC20 reward token contract.
     * @param _rewardRate The number of reward tokens earned per second for the entire pool.
     */
    constructor(
        address _nftCollectionAddress,
        address _rewardTokenAddress,
        uint256 _rewardRate
    ) {
        nftCollection = IERC721(_nftCollectionAddress);
        rewardToken = IERC20(_rewardTokenAddress);
        rewardRate = _rewardRate;
        // solhint-disable-next-line not-rely-on-time
        lastUpdateTime = block.timestamp;
    }

    // --- Modifiers ---

    /**
     * @dev Modifier to update reward states for a given account.
     * @param _account The account for which to update rewards.
     */
    modifier updateReward(address _account) {
        rewardPerTokenStored = rewardPerToken();
        // solhint-disable-next-line not-rely-on-time
        lastUpdateTime = block.timestamp;

        rewards[_account] = _getRewardAmount(_account);
        userRewardPerTokenPaid[_account] = rewardPerTokenStored;
        _;
    }

    // --- Staking and Unstaking ---

    /**
     * @notice Stakes multiple NFTs.
     * @dev The caller must be the owner of the NFTs and must have approved the contract to transfer them.
     *      Updates rewards for the user before staking.
     * @param _tokenIds An array of token IDs to stake.
     */
    function stake(uint256[] calldata _tokenIds) external nonReentrant updateReward(msg.sender) {
        if (_tokenIds.length == 0) revert EmptyTokenArray();

        uint256 newStakes = _tokenIds.length;
        totalStaked += newStakes;

        for (uint256 i = 0; i < newStakes; i++) {
            uint256 tokenId = _tokenIds[i];

            if (nftCollection.ownerOf(tokenId) != msg.sender) {
                revert NotTokenOwnerOrApproved(tokenId);
            }

            stakerOf[tokenId] = msg.sender;
            _stakedTokens[msg.sender].push(tokenId);

            nftCollection.safeTransferFrom(msg.sender, address(this), tokenId);
        }

        emit Staked(msg.sender, _tokenIds);
    }

    /**
     * @notice Unstakes multiple NFTs.
     * @dev The caller must be the staker of the NFTs.
     *      Updates rewards for the user before unstaking.
     * @param _tokenIds An array of token IDs to unstake.
     */
    function unstake(uint256[] calldata _tokenIds) external nonReentrant updateReward(msg.sender) {
        if (_tokenIds.length == 0) revert EmptyTokenArray();

        uint256 unstakes = _tokenIds.length;
        totalStaked -= unstakes;

        for (uint256 i = 0; i < unstakes; i++) {
            uint256 tokenId = _tokenIds[i];

            if (stakerOf[tokenId] != msg.sender) revert NotStaker(tokenId);

            _removeStakedToken(msg.sender, tokenId);
            delete stakerOf[tokenId];

            nftCollection.safeTransferFrom(address(this), msg.sender, tokenId);
        }

        emit Unstaked(msg.sender, _tokenIds);
    }

    // --- Reward Logic ---

    /**
     * @notice Claims accumulated rewards for the message sender.
     * @dev Transfers the reward tokens to the user and resets their pending rewards.
     *      Applies updateReward modifier to ensure all rewards up to the current block are included.
     */
    function claimRewards() external nonReentrant updateReward(msg.sender) {
        uint256 rewardAmount = rewards[msg.sender];
        if (rewardAmount == 0) revert NoRewardsToClaim();

        rewards[msg.sender] = 0;
        rewardToken.safeTransfer(msg.sender, rewardAmount);

        emit RewardClaimed(msg.sender, rewardAmount);
    }

    // --- View Functions ---

    /**
     * @notice Calculates the total pending rewards for a user.
     * @param _user The address of the user.
     * @return The total amount of reward tokens claimable by the user.
     */
    function getRewardAmount(address _user) external view returns (uint256) {
        return _getRewardAmount(_user);
    }

    /**
     * @notice Returns the number of NFTs staked by a specific owner.
     * @param _owner The address of the owner.
     * @return The number of NFTs staked.
     */
    function balanceOf(address _owner) external view returns (uint256) {
        return _stakedTokens[_owner].length;
    }

    /**
     * @notice Retrieves the list of token IDs staked by a specific user.
     * @param _user The address of the user.
     * @return An array of staked token IDs.
     */
    function getStakedTokens(address _user) external view returns (uint256[] memory) {
        return _stakedTokens[_user];
    }

    /**
     * @dev Calculates the accumulated rewards per token since the last update.
     * @return The updated rewards per token value, scaled by 1e18.
     */
    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }
        // solhint-disable-next-line not-rely-on-time
        return rewardPerTokenStored + (((block.timestamp - lastUpdateTime) * rewardRate * 1e18) / totalStaked);
    }

    // --- Internal Functions ---

    /**
     * @dev Calculates the total pending rewards for a user without updating state.
     * @param _account The address of the user.
     * @return The total amount of reward tokens claimable by the user.
     */
    function _getRewardAmount(address _account) internal view returns (uint256) {
        uint256 stakedCount = _stakedTokens[_account].length;
        return rewards[_account] + ((stakedCount * (rewardPerToken() - userRewardPerTokenPaid[_account])) / 1e18);
    }

    /**
     * @notice Internal function to remove a token ID from a user's staked tokens array.
     * @dev This uses the swap-and-pop method for gas efficiency. It does not preserve order.
     * @param _user The address of the user.
     * @param _tokenId The token ID to remove.
     */
    function _removeStakedToken(address _user, uint256 _tokenId) internal {
        uint256[] storage tokenList = _stakedTokens[_user];
        uint256 lastIndex = tokenList.length - 1;

        for (uint256 i = 0; i < tokenList.length; i++) {
            if (tokenList[i] == _tokenId) {
                // Swap the found element with the last element
                tokenList[i] = tokenList[lastIndex];
                // Remove the last element
                tokenList.pop();
                return;
            }
        }
        // This should be unreachable if called correctly from unstake
        revert NotStaker(_tokenId);
    }
}
