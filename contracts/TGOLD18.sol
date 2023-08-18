// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TGOLD18 is ERC20 {
    constructor() ERC20 ("TokenizedGold", "TGOLD18") {
        _mint(msg.sender, 1e19);        // 10 full tokens of TGOLD18 assigned to me
    }
}