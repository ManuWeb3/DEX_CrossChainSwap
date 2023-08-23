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

    address private TGOLDTokenAddress;
    address private CCIP_BnMTokenAddress;
    address private immutable i_router;
    address private immutable i_link;   // to pay CCIPFee in LINK only, for now
    
    constructor (address _TGOLDToken, address _CCIP_BnMTokenAddress, address _router, address _link) 
    ERC20 ("TGOLD Token", "TGLP") {
        
        if(_TGOLDToken == address(0) || _CCIP_BnMTokenAddress == address(0) || _router == address(0) || _link == address(0)) {
            revert AddressZeroError();
        }

        TGOLDTokenAddress = _TGOLDToken;
        CCIP_BnMTokenAddress = _CCIP_BnMTokenAddress;
        i_router = _router;
        i_link = _link;
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
        
        ERC20 TGOLDToken = ERC20(TGOLDTokenAddress);          
        ERC20 CCIP_BnMToken = ERC20(CCIP_BnMTokenAddress);

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
        TGOLDToken.transferFrom(_msgSender(), address(this), _amountTGOLD);
        // At POLYGON - CCIP_BnMToken.transferFrom(_msgSender(), address(this), _amountCCIP_BnM);
        Client.EVM2AnyMessage memory evm2AnyMessage _buildCCIPMessage();
        
        bytes32 messageId = router.ccipSend();        
        
        emit AddedLiquidtyAsset1(_amountTGOLD);
        emit MessageSent(messageId);

        return (_amountTGOLD, _amountCCIP_BnM);
     }

    // custom helper f(), not standard
    function _buildCCIPMessage(address _receiver, ) internal returns (Client.EVM2AnyMessage memory) {
        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(_receiver);    // to bytes
            data: abi.encodeWithSignature("mint(address,uint256)",addressERC20Polygon, amountToMint);
            
        })
    }

    function getReserveTGOLD() public view returns (uint256) {
        return ERC20(TGOLDTokenAddress).balanceOf(address(this));   // convention - IERC20(address).balanceOf(address)
    }

    function getReserveCCIP_BnM() public view returns (uint256) {
        return ERC20(CCIP_BnMTokenAddress).balanceOf(address(this));   // convention - IERC20(address).balanceOf(address)
    }

    function getTGOLDTokenAddress() public view returns(address) {
       return TGOLDTokenAddress;
   }
}