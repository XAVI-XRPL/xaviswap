// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./XaviPair.sol";
import "./WXRP.sol";

/**
 * @title XaviRouter
 * @author Agent Xavi (Autonomous Builder on XRPL EVM)
 * @notice Router for XaviSwap - handles liquidity and swap operations
 * @dev User-facing contract with slippage protection and deadline checks
 */
contract XaviRouter is Ownable, Pausable {
    
    /// @notice Contract version
    string public constant VERSION = "1.1.0";
    
    /// @notice Factory contract address
    address public immutable factory;
    
    /// @notice Wrapped XRP contract address
    address public immutable wxrp;
    
    /// @notice Maximum swap size as percentage of pool reserves (default 30%)
    uint256 public maxSwapPercent = 30;

    /// @notice Deadline modifier - all swaps/liquidity must have valid deadline
    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "XaviRouter: EXPIRED");
        _;
    }

    constructor(address _factory, address _WXRP) Ownable(msg.sender) {
        require(_factory != address(0), "XaviRouter: ZERO_FACTORY");
        require(_WXRP != address(0), "XaviRouter: ZERO_WXRP");
        factory = _factory;
        wxrp = _WXRP;
    }

    receive() external payable {
        assert(msg.sender == wxrp);
    }

    // ============ LIQUIDITY FUNCTIONS ============

    /// @notice Add liquidity to a token pair
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external whenNotPaused ensure(deadline) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = IXaviFactory(factory).getPair(tokenA, tokenB);
        _safeTransferFrom(tokenA, msg.sender, pair, amountA);
        _safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = XaviPair(pair).mint(to);
    }

    /// @notice Add liquidity with native XRP
    function addLiquidityXRP(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountXRPMin,
        address to,
        uint256 deadline
    ) external payable whenNotPaused ensure(deadline) returns (uint256 amountToken, uint256 amountXRP, uint256 liquidity) {
        (amountToken, amountXRP) = _addLiquidity(
            token,
            wxrp,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountXRPMin
        );
        address pair = IXaviFactory(factory).getPair(token, wxrp);
        _safeTransferFrom(token, msg.sender, pair, amountToken);
        IWXRP(wxrp).deposit{value: amountXRP}();
        assert(IERC20(wxrp).transfer(pair, amountXRP));
        liquidity = XaviPair(pair).mint(to);
        
        if (msg.value > amountXRP) {
            (bool sent, ) = payable(msg.sender).call{value: msg.value - amountXRP}("");
            require(sent, "XaviRouter: XRP_REFUND_FAILED");
        }
    }

    /// @notice Remove liquidity from a token pair
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public whenNotPaused ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = IXaviFactory(factory).getPair(tokenA, tokenB);
        IERC20(pair).transferFrom(msg.sender, pair, liquidity);
        (uint256 amount0, uint256 amount1) = XaviPair(pair).burn(to);
        (address token0,) = sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, "XaviRouter: INSUFFICIENT_A_AMOUNT");
        require(amountB >= amountBMin, "XaviRouter: INSUFFICIENT_B_AMOUNT");
    }

    /// @notice Remove liquidity and receive native XRP
    function removeLiquidityXRP(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountXRPMin,
        address to,
        uint256 deadline
    ) public whenNotPaused ensure(deadline) returns (uint256 amountToken, uint256 amountXRP) {
        (amountToken, amountXRP) = removeLiquidity(
            token,
            wxrp,
            liquidity,
            amountTokenMin,
            amountXRPMin,
            address(this),
            deadline
        );
        _safeTransfer(token, to, amountToken);
        IWXRP(wxrp).withdraw(amountXRP);
        (bool sent, ) = payable(to).call{value: amountXRP}("");
        require(sent, "XaviRouter: XRP_TRANSFER_FAILED");
    }

    // ============ SWAP FUNCTIONS ============

    /// @notice Swap exact tokens for tokens
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external whenNotPaused ensure(deadline) returns (uint256[] memory amounts) {
        amounts = getAmountsOut(amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "XaviRouter: INSUFFICIENT_OUTPUT_AMOUNT");
        _checkMaxSwapSize(path[0], path[1], amounts[0]);
        _safeTransferFrom(path[0], msg.sender, IXaviFactory(factory).getPair(path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
    }

    /// @notice Swap tokens for exact tokens
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external whenNotPaused ensure(deadline) returns (uint256[] memory amounts) {
        amounts = getAmountsIn(amountOut, path);
        require(amounts[0] <= amountInMax, "XaviRouter: EXCESSIVE_INPUT_AMOUNT");
        _checkMaxSwapSize(path[0], path[1], amounts[0]);
        _safeTransferFrom(path[0], msg.sender, IXaviFactory(factory).getPair(path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
    }

    /// @notice Swap exact XRP for tokens
    function swapExactXRPForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable whenNotPaused ensure(deadline) returns (uint256[] memory amounts) {
        require(path[0] == wxrp, "XaviRouter: INVALID_PATH");
        amounts = getAmountsOut(msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "XaviRouter: INSUFFICIENT_OUTPUT_AMOUNT");
        _checkMaxSwapSize(path[0], path[1], amounts[0]);
        IWXRP(wxrp).deposit{value: amounts[0]}();
        assert(IERC20(wxrp).transfer(IXaviFactory(factory).getPair(path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
    }

    /// @notice Swap tokens for exact XRP
    function swapTokensForExactXRP(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external whenNotPaused ensure(deadline) returns (uint256[] memory amounts) {
        require(path[path.length - 1] == wxrp, "XaviRouter: INVALID_PATH");
        amounts = getAmountsIn(amountOut, path);
        require(amounts[0] <= amountInMax, "XaviRouter: EXCESSIVE_INPUT_AMOUNT");
        _checkMaxSwapSize(path[0], path[1], amounts[0]);
        _safeTransferFrom(path[0], msg.sender, IXaviFactory(factory).getPair(path[0], path[1]), amounts[0]);
        _swap(amounts, path, address(this));
        IWXRP(wxrp).withdraw(amounts[amounts.length - 1]);
        (bool sent, ) = payable(to).call{value: amounts[amounts.length - 1]}("");
        require(sent, "XaviRouter: XRP_TRANSFER_FAILED");
    }

    /// @notice Swap exact tokens for XRP
    function swapExactTokensForXRP(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external whenNotPaused ensure(deadline) returns (uint256[] memory amounts) {
        require(path[path.length - 1] == wxrp, "XaviRouter: INVALID_PATH");
        amounts = getAmountsOut(amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "XaviRouter: INSUFFICIENT_OUTPUT_AMOUNT");
        _checkMaxSwapSize(path[0], path[1], amounts[0]);
        _safeTransferFrom(path[0], msg.sender, IXaviFactory(factory).getPair(path[0], path[1]), amounts[0]);
        _swap(amounts, path, address(this));
        IWXRP(wxrp).withdraw(amounts[amounts.length - 1]);
        (bool sent, ) = payable(to).call{value: amounts[amounts.length - 1]}("");
        require(sent, "XaviRouter: XRP_TRANSFER_FAILED");
    }

    /// @notice Swap XRP for exact tokens
    function swapXRPForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable whenNotPaused ensure(deadline) returns (uint256[] memory amounts) {
        require(path[0] == wxrp, "XaviRouter: INVALID_PATH");
        amounts = getAmountsIn(amountOut, path);
        require(amounts[0] <= msg.value, "XaviRouter: EXCESSIVE_INPUT_AMOUNT");
        _checkMaxSwapSize(path[0], path[1], amounts[0]);
        IWXRP(wxrp).deposit{value: amounts[0]}();
        assert(IERC20(wxrp).transfer(IXaviFactory(factory).getPair(path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
        
        if (msg.value > amounts[0]) {
            (bool sent, ) = payable(msg.sender).call{value: msg.value - amounts[0]}("");
            require(sent, "XaviRouter: XRP_REFUND_FAILED");
        }
    }

    // ============ ADMIN FUNCTIONS ============

    /// @notice Set maximum swap percentage
    function setMaxSwapPercent(uint256 _maxSwapPercent) external onlyOwner {
        require(_maxSwapPercent > 0 && _maxSwapPercent <= 100, "XaviRouter: INVALID_PERCENT");
        maxSwapPercent = _maxSwapPercent;
    }

    /// @notice Pause all swap and liquidity operations
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause operations
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Prevent accidental ownership renounce
    function renounceOwnership() public pure override {
        revert("XaviRouter: renounce disabled");
    }

    // ============ INTERNAL FUNCTIONS ============

    function _checkMaxSwapSize(address tokenA, address tokenB, uint256 amountIn) internal view {
        (uint256 reserveIn, ) = getReserves(tokenA, tokenB);
        if (reserveIn > 0) {
            uint256 maxAmount = (reserveIn * maxSwapPercent) / 100;
            require(amountIn <= maxAmount, "XaviRouter: SWAP_TOO_LARGE");
        }
    }

    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal returns (uint256 amountA, uint256 amountB) {
        if (IXaviFactory(factory).getPair(tokenA, tokenB) == address(0)) {
            IXaviFactory(factory).createPair(tokenA, tokenB);
        }
        
        (uint256 reserveA, uint256 reserveB) = getReserves(tokenA, tokenB);
        
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, "XaviRouter: INSUFFICIENT_B_AMOUNT");
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, "XaviRouter: INSUFFICIENT_A_AMOUNT");
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function _swap(uint256[] memory amounts, address[] memory path, address _to) internal {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0 
                ? (uint256(0), amountOut) 
                : (amountOut, uint256(0));
            address to = i < path.length - 2 
                ? IXaviFactory(factory).getPair(output, path[i + 2]) 
                : _to;
            XaviPair(IXaviFactory(factory).getPair(input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }

    // ============ VIEW FUNCTIONS ============

    function sortTokens(address tokenA, address tokenB) public pure returns (address token0, address token1) {
        require(tokenA != tokenB, "XaviRouter: IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "XaviRouter: ZERO_ADDRESS");
    }

    function getReserves(address tokenA, address tokenB) public view returns (uint256 reserveA, uint256 reserveB) {
        (address token0,) = sortTokens(tokenA, tokenB);
        address pair = IXaviFactory(factory).getPair(tokenA, tokenB);
        if (pair == address(0)) return (0, 0);
        (uint256 reserve0, uint256 reserve1,) = XaviPair(pair).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) public pure returns (uint256 amountB) {
        require(amountA > 0, "XaviRouter: INSUFFICIENT_AMOUNT");
        require(reserveA > 0 && reserveB > 0, "XaviRouter: INSUFFICIENT_LIQUIDITY");
        amountB = (amountA * reserveB) / reserveA;
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) public pure returns (uint256 amountOut) {
        require(amountIn > 0, "XaviRouter: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "XaviRouter: INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) public pure returns (uint256 amountIn) {
        require(amountOut > 0, "XaviRouter: INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "XaviRouter: INSUFFICIENT_LIQUIDITY");
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }

    function getAmountsOut(uint256 amountIn, address[] memory path) public view returns (uint256[] memory amounts) {
        require(path.length >= 2, "XaviRouter: INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i; i < path.length - 1; i++) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    function getAmountsIn(uint256 amountOut, address[] memory path) public view returns (uint256[] memory amounts) {
        require(path.length >= 2, "XaviRouter: INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint256 i = path.length - 1; i > 0; i--) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(path[i - 1], path[i]);
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }

    function getVersion() external pure returns (string memory) {
        return VERSION;
    }

    // ============ HELPERS ============

    function _safeTransfer(address token, address to, uint256 value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "XaviRouter: TRANSFER_FAILED");
    }

    function _safeTransferFrom(address token, address from, address to, uint256 value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "XaviRouter: TRANSFER_FROM_FAILED");
    }
}

interface IWXRP {
    function deposit() external payable;
    function withdraw(uint256) external;
}
