// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./XaviPair.sol";

/**
 * @title XaviFactory
 * @author XAVI (Autonomous Builder on XRPL EVM)
 * @notice Factory contract for creating XaviSwap trading pairs
 * @dev Deploys new XaviPair contracts and manages protocol fees
 */
contract XaviFactory {
    
    /// @notice Address receiving protocol fees (0.05% of swaps)
    address public feeTo;
    
    /// @notice Address allowed to change feeTo
    address public feeToSetter;
    
    /// @notice Mapping of token pairs to pair contract addresses
    mapping(address => mapping(address => address)) public getPair;
    
    /// @notice Array of all created pairs
    address[] public allPairs;
    
    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint256 pairIndex
    );

    constructor(address _feeToSetter) {
        feeToSetter = _feeToSetter;
        feeTo = _feeToSetter; // Initially fees go to setter
    }

    /// @notice Get total number of pairs created
    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    /// @notice Create a new trading pair
    /// @param tokenA First token address
    /// @param tokenB Second token address
    /// @return pair Address of the created pair contract
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, "XaviFactory: IDENTICAL_ADDRESSES");
        
        // Sort tokens to ensure consistent ordering
        (address token0, address token1) = tokenA < tokenB 
            ? (tokenA, tokenB) 
            : (tokenB, tokenA);
        
        require(token0 != address(0), "XaviFactory: ZERO_ADDRESS");
        require(getPair[token0][token1] == address(0), "XaviFactory: PAIR_EXISTS");
        
        // Deploy new pair using CREATE2 for deterministic addresses
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        pair = address(new XaviPair{salt: salt}());
        
        // Initialize the pair
        XaviPair(pair).initialize(token0, token1);
        
        // Store pair in both directions for easy lookup
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);
        
        emit PairCreated(token0, token1, pair, allPairs.length - 1);
    }

    /// @notice Set the address to receive protocol fees
    /// @param _feeTo New fee recipient
    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, "XaviFactory: FORBIDDEN");
        feeTo = _feeTo;
    }

    /// @notice Transfer the ability to set fee recipient
    /// @param _feeToSetter New fee setter
    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, "XaviFactory: FORBIDDEN");
        feeToSetter = _feeToSetter;
    }
}
