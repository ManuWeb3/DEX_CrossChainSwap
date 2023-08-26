// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";                    // all 3 structs
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";     // router client (Sender)
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";     // to pay fee in LINK (1/2 options)
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";     // onlyOwner modifier

import "hardhat/console.sol";

contract CCIPSender is OwnerIsCreator {
    
    error NotEnoughLINKBalance(uint256 balanceLink, uint256 ccipSendFees);

    event MessageSent(bytes32 messageId);
    
    function sendMessage() public {
        
        address RxExchangeAddress = 0x2860bE3e5c8221837805129478b9812eb2C577dc;
        uint256 amountToMint = 1000;
        address i_link = 0x779877A7B0D9E8603169DdbD7836e478b4624789;
        address i_router = 0xD0daae2231E9CB96b94C8512223533293C3693Bf;

        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(0xbD41b26dcaCF130b40a736fA45Cf81e64F054408),                // address of CCIP_BnMMumbai to rx the encoded calldata of mint(), into bytes
            data: abi.encodeWithSignature("mint(address,uint256)", RxExchangeAddress, amountToMint),
            tokenAmounts: new Client.EVMTokenAmount[](0),   // init array with 0 element, bcz array not needed
            feeToken: i_link,
            extraArgs: ""
        });

        uint256 fees = IRouterClient(i_router).getFee(12532609583862916517, evm2AnyMessage);
        if(fees > LinkTokenInterface(i_link).balanceOf(address(this))) {
            revert NotEnoughLINKBalance(LinkTokenInterface(i_link).balanceOf(address(this)), fees);
        }

        // 2. approve router to spend LINK on SenderExchange's behalf
        LinkTokenInterface(i_link).approve((i_router), type(uint256).max);
        // no other approval as no other token transfer in place
        
        // 3. finally, ccipSend()
        bytes32 messageId = IRouterClient(i_router).ccipSend(12532609583862916517, evm2AnyMessage);

        emit MessageSent(messageId);
    }
}