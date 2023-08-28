// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";     // onlyOwner modifier
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";                    // all 3 structs
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";     // NEW - ccipReceiver() (like ccipsend in Router)
import "./Whitelisting.sol";
import "hardhat/console.sol";

contract CCIPDestContract is CCIPReceiver, Whitelisting {

    error CallFailed();
    error AddressZeroError();

    // Polygon-Mumbai's router
    constructor(address _router) CCIPReceiver(_router) {}

    function _ccipReceive(Client.Any2EVMMessage memory any2EVMMessage) 
    internal 
    override 
    onlyWhitelistedSourceChain(any2EVMMessage.sourceChainSelector)       // Make sure source chain is whitelisted   // both checks in receive   // external, hence inherited here
    onlyWhitelistedSenders(abi.decode(any2EVMMessage.sender, (address))) // Make sure the sender is whitelisted     // both checks in receive   // external, hence inherited here
    {
        (bool success, ) = Rx_EXCHANGE.call(any2EVMMessage.data);
        if(!success) {
            revert CallFailed();
        }
    }

}