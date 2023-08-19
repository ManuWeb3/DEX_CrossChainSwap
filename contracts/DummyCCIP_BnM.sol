// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DummyCCIP_BnM is ERC20 {
    constructor() ERC20 ("Dummy CCIP_BnM", "DuCCIP_BnM") {
        _mint(msg.sender, 1e19);        // 10 full tokens of DuCCIP_BnM assigned to me
    }
}