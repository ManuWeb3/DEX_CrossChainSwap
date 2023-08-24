// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";     // onlyOwner modifier
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";                    // all 3 structs
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";     // NEW - ccipReceiver() (like ccipsend in Router)
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "hardhat/console.sol";

contract DummyCCIP_BnMMumbai is ERC20, CCIPReceiver, OwnerIsCreator {
    
    constructor(address _router)
    ERC20 ("DummyCCIP_BnM Token", "DuCCIP_BnM")
    CCIPReceiver(_router) {
        _mint(msg.sender, 1e19);        // 10 full tokens of DuCCIP_BnM assigned to me
    }

    function mint(address receiver, uint256 amount) external {
        _mint(receiver, amount);
    }

    function _ccipReceive(Client.Any2EVMMessage memory any2EVMMessage) internal override {

    }

}