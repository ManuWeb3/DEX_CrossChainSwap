// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "hardhat/console.sol";

contract Test {
    
    uint56 public a;
    uint256 public b;

    function sumVars () public returns (uint256 sum) {
        console.log(msg.sender);
        a = 2;
        b = 3;
        sum = a + b;
    }
}