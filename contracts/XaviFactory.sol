// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./XaviPair.sol";

/**
 * @title XaviFactory
 * @author Agent Xavi (Autonomous Builder on XRPL EVM)
 * @notice Factory contract for creating XaviSwap trading pairs
 * @dev Deploys new XaviPair contracts and manages protocol fees
 */
contract XaviFactory is Ownable, Pausable {
    
    /// @notice Contract version
    string public constant VERSION = "1.1.0";
    
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
    event FeeToChanged(address indexed previousFeeTo, address indexed newFeeTo);
    event FeeToSetterChanged(address indexed previousSetter, address indexed newSetter);

    constructor(address _feeToSetter) Ownable(msg.sender) {
        require(_feeToSetter != address(0), "XaviFactory: ZERO_SETTER");
        feeToSetter = _feeToSetter;
        feeTo = _feeToSetter;
    }

    /// @notice Get total number of pairs created
    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    /// @notice Create a new trading pair
    /// @param tokenA First token address
    /// @param tokenB Second token address
    /// @return pair Address of the created pair contract
    function createPair(address tokenA, address tokenB) external whenNotPaused returns (address pair) {
        require(tokenA != tokenB, "XaviFactory: IDENTICAL_ADDRESSES");
        
        (address token0, address token1) = tokenA < tokenB 
            ? (tokenA, tokenB) 
            : (tokenB, tokenA);
        
        require(token0 != address(0), "XaviFactory: ZERO_ADDRESS");
        require(getPair[token0][token1] == address(0), "XaviFactory: PAIR_EXISTS");
        
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        pair = address(new XaviPair{salt: salt}());
        
        XaviPair(pair).initialize(token0, token1);
        
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);
        
        emit PairCreated(token0, token1, pair, allPairs.length - 1);
    }

    /// @notice Set the address to receive protocol fees
    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, "XaviFactory: FORBIDDEN");
        address previous = feeTo;
        feeTo = _feeTo;
        emit FeeToChanged(previous, _feeTo);
    }

    /// @notice Transfer the ability to set fee recipient
    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, "XaviFactory: FORBIDDEN");
        require(_feeToSetter != address(0), "XaviFactory: ZERO_SETTER");
        address previous = feeToSetter;
        feeToSetter = _feeToSetter;
        emit FeeToSetterChanged(previous, _feeToSetter);
    }
    
    /// @notice Pause pair creation (emergency)
    function pause() external onlyOwner {
        _pause();
    }
    
    /// @notice Unpause pair creation
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /// @notice Prevent accidental ownership renounce
    function renounceOwnership() public pure override {
        revert("XaviFactory: renounce disabled");
    }
    
    /// @notice Get contract version
    function getVersion() external pure returns (string memory) {
        return VERSION;
    }
}
