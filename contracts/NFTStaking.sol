// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title NFTStaking
 * @author Your Name
 * @notice A contract for staking NFTs to earn ERC20 token rewards.
 * This contract supports staking and withdrawing single or multiple NFTs,
 * and claiming rewards.
 * It includes batch operations for gas efficiency when handling multiple assets.
 */
contract NFTStaking is Ownable, ERC721Holder, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    // --- Events ---

    event TokenStaked(address indexed staker, address indexed nftAddress, uint256 indexed tokenId, uint256 timestamp);
    event TokensStakedBatch(address indexed staker, uint256 tokenCount);
    event TokenWithdrawn(address indexed staker, address indexed nftAddress, uint256 indexed tokenId, uint256 timestamp);
    event TokensWithdrawnBatch(address indexed staker, uint256 tokenCount);
    event RewardClaimed(address indexed staker, address nftAddress, uint256 tokenId, uint256 rewardAmount);
    event AllRewardsClaimed(address indexed staker, uint256 totalRewardAmount);
    event RewardRateUpdated(uint256 newRate);
    event RewardTokenUpdated(address newRewardToken);

    // --- Custom Errors ---

    error ZeroAddress();
    error MismatchedArrayLengths();
    error NothingToStake();
    error NothingToWithdraw();
    error NotTokenOwner();
    error TokenNotStaked();
    error TokenAlreadyStaked();
    error NoStakedTokensToClaim();
    error NoStakedTokensFound();

    // --- State Variables ---

    /// @notice The ERC20 token used for rewards.
    IERC20 public rewardToken;

    /// @notice The amount of reward tokens distributed per second per staked NFT.
    uint256 public rewardRate;

    /// @notice Information about each staked token.
    struct StakeInfo {
        address owner;
        uint256 timestamp;
    }

    // Mapping: nft_address => token_id => StakeInfo
    mapping(address => mapping(uint256 => StakeInfo)) private _stakes;

    // Mapping for stakers to find their staked collections: staker => set of collection addresses
    mapping(address => EnumerableSet.AddressSet) private _stakedCollections;

    // Mapping for stakers to find their tokens in a collection: staker => collection_address => set of token_ids
    mapping(address => mapping(address => EnumerableSet.UintSet)) private _stakedTokens;

    /// @notice Total number of tokens staked by a user.
    mapping(address => uint256) public totalStaked;

    // --- Constructor ---

    /**
     * @notice Initializes the contract with the reward token and rate.
     * @param _rewardToken The address of the ERC20 reward token.
     * @param _rewardRate The initial reward rate per second.
     */
    constructor(address _rewardToken, uint256 _rewardRate) {
        if (_rewardToken == address(0)) revert ZeroAddress();
        rewardToken = IERC20(_rewardToken);
        rewardRate = _rewardRate;
    }

    // --- Owner Functions ---

    /**
     * @notice Updates the reward rate.
     * @param _rewardRate The new reward rate per second.
     */
    function setRewardRate(uint256 _rewardRate) external onlyOwner {
        rewardRate = _rewardRate;
        emit RewardRateUpdated(_rewardRate);
    }

    /**
     * @notice Updates the reward token address.
     * @param _rewardToken The address of the new ERC20 reward token.
     */
    function setRewardToken(address _rewardToken) external onlyOwner {
        if (_rewardToken == address(0)) revert ZeroAddress();
        rewardToken = IERC20(_rewardToken);
        emit RewardTokenUpdated(_rewardToken);
    }

    // --- Staking Logic ---

    /**
     * @notice Stakes a single NFT.
     * @dev The contract must be approved to transfer the NFT.
     * @param _nftAddress The address of the NFT contract.
     * @param _tokenId The ID of the token to stake.
     */
    function stake(address _nftAddress, uint256 _tokenId) external {
        if (_nftAddress == address(0)) revert ZeroAddress();

        IERC721(_nftAddress).safeTransferFrom(msg.sender, address(this), _tokenId);
        _stake(msg.sender, _nftAddress, _tokenId);
        emit TokenStaked(msg.sender, _nftAddress, _tokenId, block.timestamp);
    }

    /**
     * @notice Stakes multiple NFTs from different collections in a single transaction.
     * @dev The contract must be approved for all NFTs. `nftAddresses` and `tokenIds` arrays must match in length.
     * @param nftAddresses An array of NFT contract addresses.
     * @param tokenIds A nested array of token IDs, where tokenIds[i] corresponds to nftAddresses[i].
     */
    function stakeBatch(address[] calldata nftAddresses, uint256[][] calldata tokenIds) external {
        if (nftAddresses.length != tokenIds.length) revert MismatchedArrayLengths();
        
        address staker = msg.sender;
        uint256 totalTokensToStake = 0;

        for (uint256 i = 0; i < nftAddresses.length; i++) {
            address nftAddress = nftAddresses[i];
            if (nftAddress == address(0)) revert ZeroAddress();
            uint256[] calldata ids = tokenIds[i];
            
            for (uint256 j = 0; j < ids.length; j++) {
                uint256 tokenId = ids[j];
                
                IERC721(nftAddress).safeTransferFrom(staker, address(this), tokenId);
                _stake(staker, nftAddress, tokenId);
                unchecked {
                    totalTokensToStake++;
                }
            }
        }
        
        if (totalTokensToStake == 0) revert NothingToStake();
        emit TokensStakedBatch(staker, totalTokensToStake);
    }

    // --- Withdrawal Logic ---

    /**
     * @notice Withdraws a single staked NFT.
     * @dev Does not claim pending rewards. Use `claimReward` or `claimAllRewards` first.
     * @param _nftAddress The address of the NFT contract.
     * @param _tokenId The ID of the token to withdraw.
     */
    function withdraw(address _nftAddress, uint256 _tokenId) external {
        _withdraw(msg.sender, _nftAddress, _tokenId);
        
        IERC721(_nftAddress).safeTransferFrom(address(this), msg.sender, _tokenId);
        emit TokenWithdrawn(msg.sender, _nftAddress, _tokenId, block.timestamp);
    }

    /**
     * @notice Withdraws multiple NFTs from different collections in a single transaction.
     * @dev Does not claim pending rewards. Use `claimAllRewards` first for better gas usage.
     * @param nftAddresses An array of NFT contract addresses.
     * @param tokenIds A nested array of token IDs, where tokenIds[i] corresponds to nftAddresses[i].
     */
    function withdrawBatch(address[] calldata nftAddresses, uint256[][] calldata tokenIds) external {
        if (nftAddresses.length != tokenIds.length) revert MismatchedArrayLengths();
        
        address staker = msg.sender;
        uint256 totalTokensToWithdraw = 0;

        for (uint256 i = 0; i < nftAddresses.length; i++) {
            address nftAddress = nftAddresses[i];
            uint256[] calldata ids = tokenIds[i];
            
            for (uint256 j = 0; j < ids.length; j++) {
                uint256 tokenId = ids[j];
                _withdraw(staker, nftAddress, tokenId);
                IERC721(nftAddress).safeTransferFrom(address(this), staker, tokenId);

                unchecked {
                    totalTokensToWithdraw++;
                }
            }
        }
        
        if (totalTokensToWithdraw == 0) revert NothingToWithdraw();
        emit TokensWithdrawnBatch(staker, totalTokensToWithdraw);
    }

    // --- Reward Logic ---

    /**
     * @notice Claims rewards for a single staked NFT.
     * @dev The reward timer for the NFT is reset upon claiming.
     * @param _nftAddress The address of the NFT contract.
     * @param _tokenId The ID of the token to claim rewards for.
     */
    function claimReward(address _nftAddress, uint256 _tokenId) external nonReentrant {
        uint256 reward = _claimRewardFor(msg.sender, _nftAddress, _tokenId);
        
        if (reward > 0) {
            rewardToken.transfer(msg.sender, reward);
        }

        emit RewardClaimed(msg.sender, _nftAddress, _tokenId, reward);
    }
    
    /**
     * @notice Claims all pending rewards for all of the user's staked NFTs.
     * @dev This function iterates through all of the user's staked tokens. It may be gas-intensive
     * for users with a very large number of staked NFTs. The reward timer is reset for each NFT.
     */
    function claimAllRewards() external nonReentrant {
        address staker = msg.sender;
        uint256 totalReward = 0;

        address[] memory collections = _stakedCollections[staker].values();
        if (collections.length == 0) revert NoStakedTokensToClaim();

        for (uint256 i = 0; i < collections.length; i++) {
            address nftAddress = collections[i];
            uint256[] memory tokenIds = _stakedTokens[staker][nftAddress].values();
            
            for (uint256 j = 0; j < tokenIds.length; j++) {
                StakeInfo storage stake = _stakes[nftAddress][tokenIds[j]];
                uint256 reward = (block.timestamp - stake.timestamp) * rewardRate;
                if (reward > 0) {
                    totalReward += reward;
                    stake.timestamp = block.timestamp; // Reset reward timer
                }
            }
        }

        if (totalReward == 0) revert NoStakedTokensToClaim();

        rewardToken.transfer(staker, totalReward);
        emit AllRewardsClaimed(staker, totalReward);
    }

    // --- View Functions ---

    /**
     * @notice Calculates the pending rewards for a single staked NFT.
     * @param _staker The address of the staker.
     * @param _nftAddress The address of the NFT contract.
     * @param _tokenId The ID of the token.
     * @return The amount of pending reward tokens.
     */
    function calculateRewards(address _staker, address _nftAddress, uint256 _tokenId) external view returns (uint256) {
        StakeInfo storage stake = _stakes[_nftAddress][_tokenId];
        if (stake.owner != _staker) return 0;
        return (block.timestamp - stake.timestamp) * rewardRate;
    }

    /**
     * @notice Retrieves all staked tokens for a given staker.
     * @param _staker The address of the staker.
     * @return nftContracts An array of staked NFT contract addresses.
     * @return tokens A nested array where tokens[i] contains the token IDs for nftContracts[i].
     */
    function getStakedTokens(address _staker) external view returns (address[] memory nftContracts, uint256[][] memory tokens) {
        nftContracts = _stakedCollections[_staker].values();
        tokens = new uint256[][](nftContracts.length);

        for (uint256 i = 0; i < nftContracts.length; i++) {
            tokens[i] = _stakedTokens[_staker][nftContracts[i]].values();
        }
    }
    
    /**
     * @notice Retrieves staked tokens for multiple users, returning ABI-encoded data for each.
     * @dev This is a gas-intensive view function. Off-chain clients should decode the bytes array.
     * Each element of the returned bytes array is `abi.encode(address[] memory, uint256[][] memory)`.
     * @param stakers An array of staker addresses to query.
     * @return A bytes array where each element corresponds to a staker's encoded data.
     */
    function getMultiStakedTokens(address[] calldata stakers) external view returns (bytes[] memory) {
        bytes[] memory results = new bytes[](stakers.length);
        
        for (uint256 i = 0; i < stakers.length; i++) {
            address staker = stakers[i];
            (address[] memory nftContracts, uint256[][] memory tokens) = getStakedTokens(staker);
            results[i] = abi.encode(nftContracts, tokens);
        }
        
        return results;
    }

    // --- Internal Functions ---

    /**
     * @notice Internal logic to create a stake.
     * @param _staker The address of the staker.
     * @param _nftAddress The address of the NFT contract.
     * @param _tokenId The ID of the token.
     */
    function _stake(address _staker, address _nftAddress, uint256 _tokenId) internal {
        if (_stakes[_nftAddress][_tokenId].owner != address(0)) revert TokenAlreadyStaked();

        _stakes[_nftAddress][_tokenId] = StakeInfo(_staker, block.timestamp);
        _stakedCollections[_staker].add(_nftAddress);
        _stakedTokens[_staker][_nftAddress].add(_tokenId);
        
        unchecked {
            totalStaked[_staker]++;
        }
    }

    /**
     * @notice Internal logic to remove a stake.
     * @param _staker The address of the staker.
     * @param _nftAddress The address of the NFT contract.
     * @param _tokenId The ID of the token.
     */
    function _withdraw(address _staker, address _nftAddress, uint256 _tokenId) internal {
        if (_stakes[_nftAddress][_tokenId].owner != _staker) revert NotTokenOwner();

        delete _stakes[_nftAddress][_tokenId];
        
        EnumerableSet.UintSet storage tokenSet = _stakedTokens[_staker][_nftAddress];
        tokenSet.remove(_tokenId);
        
        if (tokenSet.length() == 0) {
            _stakedCollections[_staker].remove(_nftAddress);
        }

        unchecked {
            totalStaked[_staker]--;
        }
    }

    /**
     * @notice Internal logic to claim rewards for a single token and reset its timer.
     * @return The amount of rewards claimed.
     */
    function _claimRewardFor(address _staker, address _nftAddress, uint256 _tokenId) internal returns (uint256) {
        StakeInfo storage stake = _stakes[_nftAddress][_tokenId];
        if (stake.owner != _staker) revert NotTokenOwner();
        
        uint256 reward = (block.timestamp - stake.timestamp) * rewardRate;
        if (reward > 0) {
            stake.timestamp = block.timestamp;
        }

        return reward;
    }
}
