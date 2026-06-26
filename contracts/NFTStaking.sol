// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title NFTStaking
 * @author Your Name/Company
 * @notice This is a base contract for an NFT staking platform.
 * @dev This abstract contract provides the core foundation, state variables, events, and errors
 * for a system where users can stake ERC721 tokens to earn ERC20 token rewards.
 * It implements Ownable for administrative control, ReentrancyGuard for security,
 * and IERC721Receiver to safely accept NFTs.
 */
abstract contract NFTStaking is IERC721Receiver, Ownable, ReentrancyGuard {
    // =============================================================
    //                           STATE
    // =============================================================

    /// @notice The ERC721 NFT collection that can be staked.
    IERC721 public immutable nftCollection;

    /// @notice The ERC20 token used for distributing rewards.
    IERC20 public immutable rewardsToken;

    /// @notice Total number of NFTs currently staked in the contract.
    uint256 public totalStaked;

    /**
     * @notice A struct to store information about a staked NFT.
     * @param owner The address of the staker.
     * @param timestamp The block timestamp when the NFT was staked.
     */
    struct StakerInfo {
        address owner;
        uint256 timestamp;
    }

    /// @notice Mapping from a staked tokenId to its StakerInfo.
    mapping(uint256 => StakerInfo) public stakers;

    // =============================================================
    //                          ERRORS
    // =============================================================

    /// @notice Thrown when an address that is not the token owner tries to stake.
    error NFTStaking__NotTokenOwner();

    /// @notice Thrown when trying to stake a token that is already staked.
    error NFTStaking__TokenAlreadyStaked();

    /// @notice Thrown when trying to interact with a token that is not staked.
    error NFTStaking__TokenNotStaked();

    /// @notice Thrown when an address other than the staker tries to unstake.
    error NFTStaking__NotStaker();

    /// @notice Thrown when attempting an action that requires staked tokens, but none are staked.
    error NFTStaking__NoTokensStaked();

    /// @notice Thrown when a zero address is provided for critical contract addresses.
    error NFTStaking__ZeroAddress();

    // =============================================================
    //                           EVENTS
    // =============================================================

    /// @notice Emitted when one or more tokens are staked.
    /// @param owner The address of the account that staked the tokens.
    /// @param tokenId The ID of the token that was staked.
    event TokenStaked(address indexed owner, uint256 indexed tokenId);

    /// @notice Emitted when one or more tokens are unstaked.
    /// @param owner The address of the account that unstaked the tokens.
    /// @param tokenId The ID of the token that was unstaked.
    event TokenUnstaked(address indexed owner, uint256 indexed tokenId);

    /// @notice Emitted when a user claims their staking rewards.
    /// @param staker The address of the account claiming rewards.
    /// @param amount The amount of reward tokens claimed.
    event RewardsClaimed(address indexed staker, uint256 amount);

    // =============================================================
    //                        CONSTRUCTOR
    // =============================================================

    /**
     * @notice Initializes the staking contract.
     * @param _nftCollectionAddress The address of the ERC721 NFT contract.
     * @param _rewardsTokenAddress The address of the ERC20 rewards token contract.
     */
    constructor(address _nftCollectionAddress, address _rewardsTokenAddress) {
        if (_nftCollectionAddress == address(0) || _rewardsTokenAddress == address(0)) {
            revert NFTStaking__ZeroAddress();
        }
        nftCollection = IERC721(_nftCollectionAddress);
        rewardsToken = IERC20(_rewardsTokenAddress);
    }

    // =============================================================
    //                   ERC721 RECEIVER HOOK
    // =============================================================

    /**
     * @dev See {IERC721Receiver-onERC721Received}.
     * This contract must implement this function to be able to receive NFTs
     * via `safeTransferFrom`.
     * It is not intended to be called directly.
     */
    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    // =============================================================
    //                 VIRTUAL CORE FUNCTIONS
    // =============================================================

    /**
     * @notice Stakes multiple NFTs.
     * @dev The caller must have approved this contract to transfer their NFTs.
     * This function is virtual and should be implemented by child contracts.
     * @param tokenIds An array of token IDs to be staked.
     */
    function stake(uint256[] calldata tokenIds) public virtual;

    /**
     * @notice Unstakes multiple NFTs.
     * @dev Only the original staker can unstake their NFTs.
     * This function is virtual and should be implemented by child contracts.
     * @param tokenIds An array of token IDs to be unstaked.
     */
    function unstake(uint256[] calldata tokenIds) public virtual;

    /**
     * @notice Claims accumulated rewards.
     * @dev This function is virtual and should be implemented by child contracts.
     */
    function claimRewards() public virtual;

    // =============================================================
    //                    VIRTUAL VIEW FUNCTIONS
    // =============================================================

    /**
     * @notice Calculates the total pending rewards for a given staker.
     * @dev This function is virtual and should be implemented by child contracts.
     * @param staker The address of the staker.
     * @return The amount of claimable reward tokens.
     */
    function calculateRewards(address staker) public view virtual returns (uint256);

    /**
     * @notice Retrieves the token IDs staked by a specific address.
     * @dev This function is virtual and may be gas-intensive if a user has many tokens.
     * Consider off-chain solutions for production use.
     * @param staker The address to query.
     * @return An array of token IDs staked by the user.
     */
    function getStakedTokens(address staker) public view virtual returns (uint256[] memory);
}
