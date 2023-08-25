// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";                    // all 3 structs
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";     // router client (Sender)
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";     // to pay fee in LINK (1/2 options)
import "./Whitelisting.sol";
import "./Withdraw.sol";
import "hardhat/console.sol";
// included in Whitelisting and Withdraw
//import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";     // onlyOwner modifier

contract SenderExchange is ERC20, Whitelisting, Withdraw {

    error AddressZeroError();
    error NotEnoughLINKBalance(uint256 _linkBalance, uint256 ccipFees);
    error InsufficientERC20Input();

    event MessageSent(bytes32 messageId);   // standard type for a msgId returned by router.ccipSend()
    event MessageReceived(bytes32 messageId);
    event AddedLiquidtyAsset1(uint256 amountTGOLD);

    address private TGOLDAddress;
    address private CCIP_BnMSepoliaAddress;
    address private immutable i_router;
    address private immutable i_link;       // to pay CCIPFee in LINK only, for now
    address private RxExchangeAddress;      // Receiver # 1 (EOA for 1st trial)
    address private CCIP_BnMMumbaiAddress;  // Receiver # 2

    constructor 
    (address _TGOLDTokenAddress, 
    address _CCIP_BnMSepoliaAddress, 
    address _router, 
    address _link,
    address _RxExchangeAddress,
    address _CCIP_BnMMumbaiAddress)
    ERC20 ("TGOLD LP Token", "TGLP") {
        
        if(_TGOLDTokenAddress == address(0) || 
        _CCIP_BnMSepoliaAddress == address(0) || 
        _router == address(0) || 
        _link == address(0) ||
        _RxExchangeAddress == address(0) ||
        _CCIP_BnMMumbaiAddress == address(0)
        ) 
        {
            revert AddressZeroError();
        }

        TGOLDAddress = _TGOLDTokenAddress;
        CCIP_BnMSepoliaAddress = _CCIP_BnMSepoliaAddress;
        i_router = _router;
        i_link = _link;
        RxExchangeAddress = _RxExchangeAddress;
        CCIP_BnMMumbaiAddress = _CCIP_BnMMumbaiAddress;
    }

    /**
    * @dev Adds 2 liquidityPool assets to the exchange.
    * @notice
    * @param _amountTGOLD TG Tokens deposited by the LP
    * @param _amountCCIP_BnM CCIP_BnM tokens deposited by the LP
    */
    function addLiquidity(uint256 _amountTGOLD, uint256 _amountCCIP_BnM) external returns (uint256) {
        uint256 liquidity;
        uint256 TGOLDReserve = getReserveTGOLD();           // TG Reserve, 1st addLiq -> TG reserve = 0, BUT later txns (later-1) reserve-value
        uint256 CCIP_BnMReserve = getReserveCCIP_BnM();     // 
        
        console.log("TGOLDReserve: ", TGOLDReserve);
        console.log("CCIP_BnMReserve: ", CCIP_BnMReserve);

        ERC20 TGOLDToken = ERC20(TGOLDAddress);          
        ERC20 CCIP_BnMToken = ERC20(CCIP_BnMSepoliaAddress);

        if(TGOLDReserve == 0) {
            // Step # 1: 
            _addBothTokensInLP(TGOLDToken, _amountTGOLD, CCIP_BnMToken, _amountCCIP_BnM);
            // Step # 2:
            liquidity = _amountTGOLD;
        } 
        else {
            // Following the Golden Ratio:
            uint256 CCIP_BnMTokenAmount = (_amountTGOLD * CCIP_BnMReserve) / TGOLDReserve;
            if(_amountCCIP_BnM < CCIP_BnMTokenAmount) {
                revert InsufficientERC20Input();
            }
            // Step # 1:
            _addBothTokensInLP(TGOLDToken, _amountTGOLD, CCIP_BnMToken, CCIP_BnMTokenAmount);
            // Step # 2:
            liquidity = (_amountTGOLD * totalSupply())  / TGOLDReserve;
        }

        _mint(_msgSender(), liquidity);
        return liquidity;
   }

   receive() external payable {}

   fallback() external payable {}

    // ================================
    // GETTERS / Other Helper or internal functions

    /**
     * @dev returns the amount of Eth/TG tokens that are required to be returned to the user/trader upon swap
     * @param _amountTGOLD amount of TGOLD input
     * @param _amountCCIP_BnM amount of CCIP_BnM input
     */
    function _addBothTokensInLP(ERC20 TGOLDToken, uint256 _amountTGOLD, ERC20 CCIP_BnMToken, uint256 _amountCCIP_BnM) internal /*returns (uint256, uint256)*/ {
        // post manual approval of Exchange.sol as the Spender of TGOLD on behalf of LProvider
        // adding 1 token to LPool
        TGOLDToken.transferFrom(_msgSender(), address(this), _amountTGOLD);
        // adding 2nd token to LPool
        CCIP_BnMToken.transferFrom(_msgSender(), address(this), _amountCCIP_BnM);

        /*
        console.log("Transferred both hte tokens");
        // Let's now send the msg to CCIP_BnMMumbai to mint(RxExchange.sol, _amountCCIP_BnM) and create Liquidity
        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessageAddLiq(CCIP_BnMMumbaiAddress, _amountCCIP_BnM);
        
        // destChainSelector: added in SendMsgPayLink() of PTT.sol
        uint64 destChainSelector = 16015286601757825753;
        IRouterClient router = IRouterClient(i_router);
        
        // 1. check LINK fee
        uint256 fees = router.getFee(destChainSelector, evm2AnyMessage);
        if(fees > ERC20(i_link).balanceOf(address(this))) {
            revert NotEnoughLINKBalance(ERC20(i_link).balanceOf(address(this)), fees);
        }

        // 2. approve router to spend LINK on SenderExchange's behalf
        ERC20(i_link).approve((i_router), fees);
        // no other approval as no other token transfer in place
        
        // 3. finally, ccipSend()
        bytes32 messageId = router.ccipSend(destChainSelector, evm2AnyMessage);        
        */

        emit AddedLiquidtyAsset1(_amountTGOLD);
        // emit MessageSent(messageId);

        // return (_amountTGOLD, messageId);
     }

    // custom helper f(), not standard
    // only 2-step process this time as no tokens meant to be transferred across
    // _receiver = CCIPBnMMumbaiAddress (ERC20 Token)
    function _buildCCIPMessageAddLiq(address _receiver, uint256 amountToMint) internal view returns (Client.EVM2AnyMessage memory) {
        // addressRxExchange: Rx Exchange deployed on Mumbai
        // amountToMint: amount added for CCIP_BnM token (dep. on Mumbai) in addLiquidity() in SenderExchange
        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(_receiver),                // address of CCIP_BnMMumbai to rx the encoded calldata of mint(), into bytes
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