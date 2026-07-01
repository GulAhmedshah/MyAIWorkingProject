import React, { memo } from 'react';

/**
 * @dev A checkmark icon component for indicating selection.
 */
const CheckmarkIcon = () => (
  <svg
    className="w-16 h-16 text-green-400"
    fill="none"
    stroke="currentColor"
    viewBox="0 0 24 24"
    xmlns="http://www.w3.org/2000/svg"
  >
    <path
      strokeLinecap="round"
      strokeLinejoin="round"
      strokeWidth="2"
      d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
    ></path>
  </svg>
);

/**
 * @dev Represents a single NFT card in the grid.
 * Optimized with React.memo to prevent re-renders unless props change.
 */
const NFTCard = memo(({ token, onSelect, isSelected }) => {
  const handleSelect = () => {
    onSelect(token.id);
  };

  // Fallback image in case token.image is not provided
  const imageUrl = token.image || `https://via.placeholder.com/300?text=NFT+${token.id}`;

  return (
    <div
      role="checkbox"
      aria-checked={isSelected}
      aria-label={`Select NFT ${token.name || `#${token.id}`}`}
      tabIndex="0"
      onClick={handleSelect}
      onKeyPress={(e) => (e.key === 'Enter' || e.key === ' ') && handleSelect()}
      className={`
        relative group cursor-pointer aspect-square rounded-xl overflow-hidden 
        bg-gradient-to-br from-gray-800 to-slate-900
        border-2 ${isSelected ? 'border-green-500' : 'border-transparent'}
        transition-all duration-300 ease-in-out hover:scale-105 hover:shadow-lg hover:shadow-blue-500/20
      `}
    >
      <img
        src={imageUrl}
        alt={token.name || `NFT #${token.id}`}
        className="w-full h-full object-cover transition-opacity duration-300 group-hover:opacity-80"
        loading="lazy"
      />
      
      <div className="absolute bottom-0 left-0 right-0 p-3 bg-black/50 backdrop-blur-sm">
        <p className="text-white font-semibold truncate">{token.name || `Token #${token.id}`}</p>
      </div>

      {isSelected && (
        <div className="absolute inset-0 bg-black/60 flex items-center justify-center pointer-events-none">
          <CheckmarkIcon />
        </div>
      )}
    </div>
  );
});

NFTCard.displayName = 'NFTCard';

/**
 * @dev A component to display a grid of NFTs, with support for selection,
 * loading states, and empty states. It is optimized for performance.
 * @param {Array<object>} tokens - Array of token objects. Each object should have at least {id, name, image}.
 * @param {Function} onSelect - Callback function triggered when an NFT is selected. Receives tokenId.
 * @param {Array<string|number>} selected - An array of selected token IDs.
 * @param {boolean} isLoading - If true, displays a skeleton loading grid.
 */
const NFTGrid = ({ tokens = [], onSelect, selected = [], isLoading = false }) => {

  if (isLoading) {
    return (
      <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-6 gap-4 md:gap-6">
        {Array.from({ length: 12 }).map((_, index) => (
          <div key={index} className="aspect-square bg-slate-800 rounded-xl animate-pulse" />
        ))}
      </div>
    );
  }

  if (!tokens || tokens.length === 0) {
    return (
      <div className="flex items-center justify-center text-center h-64 bg-slate-800/50 rounded-lg">
        <div>
          <h3 className="text-xl font-semibold text-white">No NFTs Found</h3>
          <p className="text-slate-400 mt-2">You do not own any NFTs from this collection, or they are currently all staked.</p>
        </div>
      </div>
    );
  }

  return (
    <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-6 gap-4 md:gap-6">
      {tokens.map(token => (
        <NFTCard 
          key={token.id} 
          token={token} 
          onSelect={onSelect} 
          isSelected={selected.includes(token.id)} 
        />
      ))}
    </div>
  );
};

export default memo(NFTGrid);
