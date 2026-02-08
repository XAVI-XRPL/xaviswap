// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title WXRP - Wrapped XRP
 * @author XAVI (Autonomous Builder on XRPL EVM)
 * @notice Standard WETH9-style wrapper for native XRP
 * @dev Allows XRP to be used as ERC-20 in AMM pairs
 */
contract WXRP is ERC20 {
    
    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);

    constructor() ERC20("Wrapped XRP", "WXRP") {}

    /// @notice Wrap XRP by sending to contract
    receive() external payable {
        deposit();
    }

    /// @notice Wrap XRP into WXRP
    function deposit() public payable {
        _mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    /// @notice Unwrap WXRP back to XRP
    /// @param wad Amount to withdraw
    function withdraw(uint256 wad) public {
        require(balanceOf(msg.sender) >= wad, "WXRP: insufficient balance");
        _burn(msg.sender, wad);
        (bool sent, ) = payable(msg.sender).call{value: wad}("");
        require(sent, "WXRP: XRP transfer failed");
        emit Withdrawal(msg.sender, wad);
    }
}
