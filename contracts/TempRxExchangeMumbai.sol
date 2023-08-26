// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TempRxExchangeMumbai {

    error AddressZeroError();

    address private immutable i_dummyCCIP_BnMMumbai;

    constructor(address _DummyCCIP_BnMMumbai) {
        if (_DummyCCIP_BnMMumbai == address(0)) {
            
            revert AddressZeroError();
        }
        i_dummyCCIP_BnMMumbai = _DummyCCIP_BnMMumbai; // ERC20 token that mints() on Mumbai
    }

    function getReserveCCIP_BnM() public view returns (uint256) {
        return ERC20(i_dummyCCIP_BnMMumbai).balanceOf(address(this));   // convention - IERC20(address).balanceOf(address)
    }
}