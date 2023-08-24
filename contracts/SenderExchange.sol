// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";                    // all 3 structs
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";     // onlyOwner modifier
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";     // router client (Sender)
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";     // to pay fee in LINK (1/2 options)
import "hardhat/console.sol";

contract SenderExchange is ERC20, OwnerIsCreator {
    
    error AddressZeroError();

    event MessageSent(bytes32 messageId);   // standard type for a msgId returned by router.ccipSend()
    event MessageReceived(bytes32 messageId);
    event AddedLiquidtyAsset1(uint256 amountTGOLD);

    address private TGOLDAddress;
    address private CCIP_BnMSepoliaAddress;
    address private immutable i_router;
    address private immutable i_link;       // to pay CCIPFee in LINK only, for now
    address private RxExchangeAddress;      // Receiver # 1
    address private CCIP_BnMMumbaiAddress;  // Receiver # 2
    
    constructor 
    (address _TGOLDTokenAddress, 
    address _CCIP_BnMSepoliaAddress, 
    address _router, 
    address _link,
    address _RxExchangeAddress)
    ERC20 ("TGOLD Token", "TGLP") {
        
        if(_TGOLDTokenAddress == address(0) || 
        _CCIP_BnMSepoliaAddress == address(0) || 
        _router == address(0) || 
        _link == address(0) ||
        _RxExchangeAddress == address(0)
        ) 
        {
            revert AddressZeroError();
        }

        TGOLDAddress = _TGOLDTokenAddress;
        CCIP_BnMSepoliaAddress = _CCIP_BnMSepoliaAddress;
        i_router = _router;
        i_link = _link;
        RxExchangeAddress = _RxExchangeAddress;
    }

    /**
    * @dev Adds 2 liquidityPool assets to the exchange.
    * @notice
    * @param _amountTGOLD TG Tokens deposited by the LP
    * @param _amountCCIP_BnM CCIP_BnM tokens deposited by the LP
    */
    function addLiquidity(uint256 _amountTGOLD, uint256 _amountCCIP_BnM) public returns (uint256) {
        uint256 liquidity;
        uint256 TGOLDReserve = getReserveTGOLD();   // TG Reserve, 1st addLiq -> TG reserve = 0, BUT later txns (later-1) reserve-value
        uint256 CCIP_BnMReserve = getReserveCCIP_BnM();
        
        ERC20 TGOLDToken = ERC20(TGOLDAddress);          
        ERC20 CCIP_BnMToken = ERC20(CCIP_BnMSepoliaAddress);

        if(TGOLDReserve == 0) {
            _addBothTokensInLP(TGOLDToken, _amountTGOLD, CCIP_BnMToken, _amountCCIP_BnM);
        } 
        else {

        }
   }

    // ================================
    // GETTERS / Other Helper or internal functions

    /**
     * @dev returns the amount of Eth/TG tokens that are required to be returned to the user/trader upon swap
     * @param _amountTGOLD amount of TGOLD input
     * @param _amountCCIP_BnM amount of CCIP_BnM input
     * @return (optional)
     */
    function _addBothTokensInLP(ERC20 TGOLDToken, uint256 _amountTGOLD, ERC20 CCIP_BnMToken, uint256 _amountCCIP_BnM) internal returns (uint256, uint256) {
        // post manual approval of Exchange.sol as the Spender of TGOLD on behalf of LProvider
        // adding 1 token to LPool
        TGOLDToken.transferFrom(_msgSender(), address(this), _amountTGOLD);

        // adding 2nd token to LPool
        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessageAddLiq(CCIP_BnMMumbaiAddress, _amountCCIP_BnM);
        
        // few checks for fee + approve LINK
        // destChainSelector: added in SendMsgPayLink() of PTT.sol
        bytes32 messageId = router.ccipSend(destChainSelector, evm2AnyMessage);        
        
        emit AddedLiquidtyAsset1(_amountTGOLD);
        emit MessageSent(messageId);

        return (_amountTGOLD, _amountCCIP_BnM);
     }

    // custom helper f(), not standard
    // only 2-step process this time as no tokens meant to be transferred across
    function _buildCCIPMessageAddLiq(address _receiver, uint256 amountToMint) internal returns (Client.EVM2AnyMessage memory) {
        // addressRxExchange: Rx Exchange deployed on Mumbai
        // amountToMint: amount added for CCIP_BnM token (dep. on Mumbai) in addLiquidity() in SenderExchange
        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(_receiver),                // to bytes
            data: abi.encodeWithSignature("mint(address,uint256)", RxExchangeAddress, amountToMint),
            tokenAmounts: new Client.EVMTokenAmount[](0),   // init array with 0 element, bcz array not needed
            feeToken: i_link,
            extraArgs: ""
        });

        return evm2AnyMessage;
    }

    function getReserveTGOLD() public view returns (uint256) {
        return ERC20(TGOLDAddress).balanceOf(address(this));   // convention - IERC20(address).balanceOf(address)
    }

    function getReserveCCIP_BnM() public view returns (uint256) {
        return ERC20(CCIP_BnMSepoliaAddress).balanceOf(address(this));   // convention - IERC20(address).balanceOf(address)
    }

    function getTGOLDTokenAddress() public view returns(address) {
       return TGOLDAddress;
   }

   function getCCIP_BnMTokenAddress() public view returns(address) {
       return CCIP_BnMSepoliaAddress;
   }

   function getRxExchangeAddress() public view returns(address) {
       return RxExchangeAddress;
   }
}