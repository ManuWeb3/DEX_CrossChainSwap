// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";     // onlyOwner modifier
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";                    // all 3 structs
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";     // NEW - ccipReceiver() (like ccipsend in Router)
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./Whitelisting.sol";
import "hardhat/console.sol";

// To add, remove liquidity of DummyCCIP_BnM on Mumbai
contract DummyCCIP_BnMMumbai is ERC20, CCIPReceiver, Whitelisting {
    
    error CallFailed();

    constructor(address _router)
    ERC20 ("DummyCCIP_BnM Token", "DuCCIP_BnM")
    CCIPReceiver(_router) {
        _mint(msg.sender, 1e19);        // 10 full tokens of DuCCIP_BnM assigned to me
    }

    function mint(address receiver, uint256 amount) external {
        _mint(receiver, amount);
    }

    function _ccipReceive(Client.Any2EVMMessage memory any2EVMMessage) 
    internal 
    override 
    onlyWhitelistedSourceChain(any2EVMMessage.sourceChainSelector)       // Make sure source chain is whitelisted   // both checks in receive   // external, hence inherited here
    onlyWhitelistedSenders(abi.decode(any2EVMMessage.sender, (address))) // Make sure the sender is whitelisted     // both checks in receive   // external, hence inherited here
    {
        (bool success, ) = address(this).call(any2EVMMessage.data);
        if(!success) {
            revert CallFailed();
        }
    }
}