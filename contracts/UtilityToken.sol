// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title UtilityToken
 * @dev An ERC-20 token for the NFT staking platform, with a fixed max supply and pausable minting.
 * The owner can mint new tokens up to the maximum supply and can pause/unpause minting.
 */
contract UtilityToken is ERC20, Ownable {
    // --- Constants ---

    /// @dev The maximum total supply of the token is 100,000,000.
    uint256 public constant MAX_SUPPLY = 100_000_000 * (10**18);

    // --- State Variables ---

    /// @dev Flag to indicate if minting is currently paused.
    bool public mintingPaused;

    // --- Errors ---

    /// @dev Reverts when minting is attempted while paused.
    error MintingIsPaused();

    /// @dev Reverts if a mint operation would exceed the maximum supply.
    /// @param available The amount of tokens that can still be minted.
    error ExceedsMaxSupply(uint256 available);

    // --- Events ---

    /// @dev Emitted when the minting state is toggled.
    /// @param isPaused The new state of the minting pause flag.
    event MintingPaused(bool isPaused);

    /// @dev Emitted when new tokens are minted.
    /// @param to The address that received the new tokens.
    /// @param amount The number of tokens minted.
    event TokensMinted(address indexed to, uint256 amount);

    // --- Constructor ---

    /**
     * @dev Sets up the token with a name, symbol, and an initial supply minted to the owner.
     * @param initialOwner The address that will own the contract and receive the initial supply.
     */
    constructor(address initialOwner) ERC20("Utility Token", "UTK") Ownable(initialOwner) {
        uint256 initialSupply = 10_000_000 * (10**18);
        _mint(initialOwner, initialSupply);
        emit TokensMinted(initialOwner, initialSupply);
    }

    // --- Minting Functions ---

    /**
     * @dev Mints new tokens to a specified address.
     * Can only be called by the owner.
     * Minting must not be paused and the total supply must not exceed MAX_SUPPLY.
     * @param to The address to mint tokens to.
     * @param amount The number of tokens to mint.
     */
    function mint(address to, uint256 amount) public onlyOwner {
        if (mintingPaused) {
            revert MintingIsPaused();
        }
        uint256 currentSupply = totalSupply();
        if (currentSupply + amount > MAX_SUPPLY) {
            revert ExceedsMaxSupply(MAX_SUPPLY - currentSupply);
        }

        _mint(to, amount);
        emit TokensMinted(to, amount);
    }

    /**
     * @dev Toggles the minting paused state.
     * Can only be called by the owner.
     */
    function toggleMinting() public onlyOwner {
        mintingPaused = !mintingPaused;
        emit MintingPaused(mintingPaused);
    }

    // --- Burning Functions ---

    /**
     * @dev Destroys a specified amount of tokens from the caller's balance.
     * This reduces the total supply.
     * @param amount The number of tokens to burn.
     */
    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }
}
