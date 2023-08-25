// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol"; // to avoid "DeclarationError: Identifier already declared"
import "hardhat/console.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";     // NEW - ccipReceiver() (like ccipsend in Router)
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";     // onlyOwner modifier
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";                    // all 3 structs

/**
@title
@notice
@dev
*/

/// All the frontend scripts also get changed with the new token-pair here

contract Exchange is ERC20, CCIPReceiver, OwnerIsCreator {

    error SendFailed();
    error AddressZeroError();
    error InsufficientERC20Input();
    error InvalidReserveQuantity();
    error InvalidInputAmount();
    error OutputAmountInsufficient();

    event AddedLiquidty(uint256 _amountTGOLD, uint256 _amountCCIP_BnM); // default ERC20 events not that discrete
    event RemovedLiquidity(uint256 _amountTGLP, uint256 _amountTGOLD, uint256 _amountCCIP_BnM);                        // default ERC20 events not that discrete
    event SwappedTGOLDToCCIP_BnM(uint256 _amountTGOLD, uint256 _amountCCIP_BnM);
    event SwappedCCIP_BnMToTGOLD(uint256 _amountTGOLD, uint256 _amountCCIP_BnM);
    event MessageSent(bytes32 messageId);   // standard type for a msgId returned by router.ccipSend()
    event MessageReceived(bytes32 messageId);

    // ERC20 is inherited as TGLP, TG, CCIP_BnM tokens are ERC20 ones
    address private TGOLDTokenAddress;
    address private CCIP_BnMTokenAddress;

    // Both TGOLD and CCIP_BnM must already be deployed, pass their addresses
    constructor (address _TGOLDToken, address _CCIP_BnMTokenAddress, address _router, address _link) 
    ERC20 ("TGOLD LP Token", "TGLP") 
    CCIPReceiver(_router)
    {
        if(_TGOLDToken == address(0) || _CCIP_BnMTokenAddress == address(0)) {
            revert AddressZeroError();
        }
        TGOLDTokenAddress = _TGOLDToken;
        CCIP_BnMTokenAddress = _CCIP_BnMTokenAddress;
    }

    /**
    * @dev Adds liquidity to the exchange.
    * @notice
    * @param _amountTGOLD TG Tokens deposited by the LP
    * @param _amountCCIP_BnM CCIP_BnM tokens deposited by the LP
    */
   // i/p "_amountTGOLD", "" refers to the TG Tokens being deplosited by the LP
   function addLiquidity(uint256 _amountTGOLD, uint256 _amountCCIP_BnM) public returns (uint256) {
        uint256 liquidity;      // in if() else() = TG LP tokens to be minted to LP, has to be calculated
        // this liquidity is always tied to TGOLDTokenAmount deposited

        uint256 TGOLDReserve = getReserveTGOLD();   // TG Reserve, 1st addLiq -> TG reserve = 0, BUT later txns (later-1) reserve-value
        uint256 CCIP_BnMReserve = getReserveCCIP_BnM();         // CCIP_BnM Reserve
        // instantiated 2 objects of type ERC20 for TGToken and CCIP_BnM contracts deployed at those addresses
        IERC20 TGOLDToken = IERC20(TGOLDTokenAddress);          // will stick with IERC20 as ABI to instantiate
        IERC20 CCIP_BnMToken = IERC20(CCIP_BnMTokenAddress);       
        // console.log("TGOLDToken: ", TGOLDToken);
        /*
        If the reserve is empty, intake any user supplied value for
        `TGOLD` and `CCIP_BnM` tokens because there is no ratio currently
        */
       if(TGOLDReserve == 0) {
        // Transfer the `TGOLDToken` from the user's account to the contract
        // transferFrom() will revert if approval not set
        
        // WHY not add this here in Solidity itself:
        // Adding TGOLD to LP
        //TGOLDToken.approve(address(this), _amountTGOLD);
        // avoid accessing msg.sender directly
        //TGOLDToken.transferFrom(_msgSender(), address(this), _amountTGOLD);
        
        // Adding CCIP_BnM to LP
        //CCIP_BnMToken.approve(address(this), _amountCCIP_BnM);
        // avoid accessing msg.sender directly
        //CCIP_BnMToken.transferFrom(_msgSender(), address(this), _amountCCIP_BnM);
        
        // STEP # 1: STRAIGHT INPUTS (No calculation): B/C Notebook # 8, pg. # 64
        _addBothTokensInLP(TGOLDToken, _amountTGOLD, CCIP_BnMToken, _amountCCIP_BnM);
        // _amountTGOLD is the amount of TG token itself whose obj is created and initialized above to exec transferFrom()
        // as this is exactly how it's done in Remix's interface

        // `liquidity` provided is equal to `TGOLD` because this is the first time user
        // is adding `TGOLD` to the contract, so whatever `TGOLD` contract will get is equal to the one supplied
        // by the user in the current `addLiquidity` call
        // `liquidity` tokens that need to be minted to the user on `addLiquidity` call should always be proportional/tied
        // to the TGOLD specified by the user bcz Liquidity (amount of LP Tokens) = TGOLDReserve
        // liquidity = "amount of LP tokens" (not full tokens, it'll be = units)
        // bcz TGOLD internally works as 10e18 units with balanceOf(ExchangeContractAddress)
        // 1st time TGOLDReserve is 0. So, whatever TGOLD gets added to LP is the liquidity itself
        // TGOLD added is returned by getReserveTGOLD()
        
        // STEP # 2: STRAIGHT INPUTS (No calculation): B/C Notebook # 8, pg. # 64
        liquidity = getReserveTGOLD();       // till this point,TG reserve != 0
        // "liquidity" var added here for clarity else directly _mint(_msgSender(), getReserveTGOLD())
        // anyway, _msgSender() = LProvider here
       }
       else {
        /*
            If the TGOLD reserve is not empty, intake any user supplied value for
            `TGOLD` and determine according to the ratio how many `CCIP_BnM` tokens
            need to be supplied to prevent any large price impacts because of the additional
            liquidity for either of the 2 assets in the pool
        */
        // TGOLDReserve should be the current TGOLDBalance subtracted by the value of current TGOLD just deposited by the user
        // in the current `addLiquidity` call
        // getReserveTGOLD() will be needed everytime the addLiq() execs
        // TGOLD amount is not auto-added as it gets added to this Exchange.sol's balance only after transferFrom() execs
         
         // Golden Ratio should always be maintained so that there are no major price impacts when adding liquidity
         // Golden Ratio here is :
         // -> (TGOLDTokenAmount user added / TGOLDTokenReserve already in the contract) = (CCIP_BnM that should be sent by the user/CCIP_BnM Reserve already in the Exchange.sol);
         // "already" = just before this txn gets mined
         // So doing some maths, (Minimum CCIP_BnM user should add) = (TGOLDTokenAmount Sent by the user * CCIP_BnMReserve /TGOLDTokenAmount Reserve);

         // CCIP_BnM - what an LP should deposit, IDEALLY, MINIMUM (>=) this should be the _amountCCIP_BnM else revert 
         // TGOLDTokenReserve - by getReserveTGOLD();
         // THE GOLDEN RATIO HAS TO BE MAINTAINED
         
         // STEP # 1: CALCULATED INPUTS (No straight) : B/C Notebook # 8, pg. # 64
         uint256 CCIP_BnMTokenAmount = (_amountTGOLD * CCIP_BnMReserve) / TGOLDReserve; // exact Golden Ratio for Liquidity calc.
        // console.log("_amountTGOLD: ", _amountTGOLD);
        // console.log("TGOLDReserve: ", TGOLDReserve);
        // console.log("CCIP_BnMReserve: ", CCIP_BnMReserve);
        // console.log("Calculated CCIP_BnMTokenAmount: ", CCIP_BnMTokenAmount);
        // calculateCCIP_BnM() in addLiquidity.js of Front end
        if(_amountCCIP_BnM < CCIP_BnMTokenAmount) {
            revert InsufficientERC20Input();
        }
        // transfer only (CCIP_BnMTokenAmount user can add) amount of `CCIP_BnM tokens` from user's account
        // to Exchange.sol

        // INTERNAL TXNs
        // TGOLDToken.approve(address(this), _amountTGOLD);
        // TGOLDToken.transferFrom(_msgSender(), address(this), _amountTGOLD);
        _addBothTokensInLP(TGOLDToken, _amountTGOLD, CCIP_BnMToken, CCIP_BnMTokenAmount);
        // calc. liquidity = LP tokens to be minted to the LProvider thru _mint()
        // 2ND FACET OF THE GOLDEN RATION w.r.t TG LP tokens (liquidity)
        // totalSupply() increases in proportion to the (_amountTGOLD/TGOLDREserve:Before adding _amountTGOLD)
        
        // STEP # 2: CALCULATED INPUTS (No straight) : B/C Notebook # 8, pg. # 64 
        // console.log("Total Supply of TGLP liquidity token: ", totalSupply());
        liquidity = (_amountTGOLD * totalSupply())  / TGOLDReserve;
        // (the golden ratio) * _totalSupply ( _totalSupply = private state var of inherited ERC20)...
        // Is LP tokens out there in the open market held by LPs, will be minted to the current LP
        // cannot use "getReserveTGOLD()" in place of TGOLDReserve in liquidity calc. above @ 144
        // as getReserveTGOLD() returns reserve value that NOW includes the newly added TGOLDTokenAmount via _addBothTokensInLP()
        }
        // COMMON STEP # 3 for if()/else(): _mint() will mint 'liquidity' amount of tokens...which ones... 
        // the ones created by the constructor during deployment of Exchange.sol (TGLP tokens)
        // NOT any other ERC20s like TGOLD/CCIP_BnM (external ERC20 contracts)
        _mint(_msgSender(), liquidity);
        // IMPORTANT:
        // the _mint() will anyway be coded after both (TGOLD + CCIPBnM tokens) have been accepted by Exchange.sol
        // to avoid the situation when user already got the TG LP tokens before its TGOLD+CCIP_BnM tokens are accepted by Exchange.sol
        return liquidity;
        // returning uint256
   }

   /**
    * @dev Returns the amount TGOLD/CCIP_BnM tokens that would be returned to the user
    * in the swap of TG LP tokens for user-funds
    */
   function removeLiquidity(uint256 _amountTGLP) public returns (uint256 , uint256) {
    if(_amountTGLP <= 0) {
        revert InvalidInputAmount();
    }

    uint256 TGOLDRes = getReserveTGOLD();                   // current TG reserve
    uint256 CCIP_BnMRes = getReserveCCIP_BnM();             // current CCIP_BnM reserve
    uint256 _totalSupplyTGLP = totalSupply();               // current TG LP tokens reserve
    // The amount of TGOLD that would be sent back to the user is based
    // on the same GOLDEN ratio:
    // Ratio is -> (TGOLD to be sent back to the user) / (current TGOLD reserve)
    // = (amount of TGLP tokens that user wants to redeem) / (total supply of TGLP tokens)
    // Then by same maths -> (TGOLD sent back to the user)
    // = (current TGOLD reserve * amount of TGLP tokens that user wants to redeem) / (total supply of TGLP tokens)
    uint256 TGOLDWithdrawn = (TGOLDRes * _amountTGLP) / _totalSupplyTGLP;      // formulae # 1, TGOLD determined, later transfer
    // The amount of CCIP_BnM token that would be sent back to the user is based
    // on a ratio
    // Ratio is -> (CCIP_BnM to be sent back to the user) / (current CCIP_BnM token reserve)
    // = (amount of TGLP tokens that user wants to redeem) / (total supply of TGLP tokens)
    uint256 CCIP_BnMWithdrawn = (CCIP_BnMRes * _amountTGLP) / _totalSupplyTGLP;     // formulae # 2, CCIP_BnM determined, later transfer
    
    // Burn the sent TGLP tokens from the user's wallet because they are already sent to
    // remove liquidity
    
    // IMPORTANT:
    // first _burn(), then .transfer() both ERC20 Tokens
    // first set the state, then transfer funds, per RE-ENTRANCY
    _burn(_msgSender(), _amountTGLP);         // burn(), as opposed to _mint()
    // _burn() applies only to TGLP token contract

    //---------------------------
    // TRANSFER # 1: (ERC20 token != ETH, hence, use transfer(), not .call{}())
    // Transfer `TGOLD` from Exchange.sol to the user's wallet
    IERC20(TGOLDTokenAddress).transfer(_msgSender(), TGOLDWithdrawn);

    // TRANSFER # 2: 
    // Transfer `CCIP_BnM` from Exchange.sol to the user's wallet
    // .transfer's _msgSender() is the contract itself (sender/from) - calling external contract
    // "_msgSender()" below is the user/to who invoked the f() removeLiq()
    
    // that's how we coded to send ERC20 tokens from inside a contract to an EOA
    IERC20(CCIP_BnMTokenAddress).transfer(_msgSender(), CCIP_BnMWithdrawn);
    //---------------------------

    emit RemovedLiquidity(_amountTGLP, TGOLDWithdrawn, CCIP_BnMWithdrawn);
    return (TGOLDWithdrawn, CCIP_BnMWithdrawn);
    }

    /**
    * @dev Swaps TGOLD for CCIP_BnM
    */

   // _minTokens sort of expectation, is what user wants / expects
   function swapTGOLDToCCIP_BnM(uint256 amountTGOLD/*=====, uint256 minCCIP_BnM*/) public {
    // Following the Golden FROMULAE of swap (Constant Product)
    uint256 CCIP_BnMRes = getReserveCCIP_BnM();
    uint256 TGOLDRes = getReserveTGOLD();
    // i/p reserve is TGOLD reserve, RIGHT before we transferred TGOLD to the contract for swap
    // bcz Denominator of Golden Formlae is (x + Delta x) and 'x' is exclusive of 'Delta x' at this point
    uint256 amountCCIP_BnM = getAmountOfTokens(       // 1% swap/trade fee taken care of in this f() above
        amountTGOLD,            
        TGOLDRes,               // always TGOLD-balance SHOULD BE the one that's before amountTGOLD adds to the TGOLD's reserve
        CCIP_BnMRes             
    );
    /* ===== if(amountCCIP_BnM < minCCIP_BnM) {
        revert OutputAmountInsufficient();
    }*/
    // Transfer ERC20 amountTGOLD to Exchange.sol (must already have been approved)
    IERC20(TGOLDTokenAddress).transferFrom(_msgSender(), address(this), amountTGOLD);
    // Transfer ERC20 amountCCIP_BnM to the user
    // when we did not create a specific interface for .transfer/From() in this contract
    // and we can use ERC20 directly as we're inheriting OZ's ERC20
    
    // Transfer swapped asset ONLY AFTER revert checked + TGOLD transferred to Exchange.sol
    //===== IERC20(CCIP_BnMTokenAddress).transfer(_msgSender(), amountCCIP_BnM);
    // will NOT send minCCIP_BnM as this does not 'obey' the Golden Formulae and will have price impact on our reserves

    // Include PTT.sol to send CCIP_BnM across
    
    /**
    uint64 destChainSelector = 12532609583862916517;
    address addressPolygonExchange = 0xf2F63Ba6C0DFE0E7D3639ce099347ad96DDf973f;
    string memory text = "Sending CCIP_BnM across";
    address addressCCIP_BnMSepolia = 0xFd57b4ddBf88a4e07fF4e34C487b99af2Fe82a05;
    
    this.sendMessagePayLINK(destChainSelector, addressPolygonExchange, text, addressCCIP_BnMSepolia, amountCCIP_BnM);
    */

    // ".this" mimics an external call to PTT.sol's f()
    // ".this" bcz sendMessagePayLINK is an external fn() of PTT.sol
    // will be inherited (bcz not private) but cannot be called internally without .this
    // also, using .this did away with the error reg. memory -> calldata "text": f() param
    emit SwappedTGOLDToCCIP_BnM(amountTGOLD, amountCCIP_BnM);
   }

   /**
    * @dev Swaps CCIP_BnM to TGOLD Tokens
    * @param minTGOLD minimum amount of TGOLD tokens that user desires to obtain after swap
    */

   function swapCCIP_BnMToTGOLD(uint256 amountCCIP_BnM, uint256 minTGOLD) public {
        // Following the Golden FROMULAE of swap (Constant Product)
        uint256 CCIP_BnMRes = getReserveCCIP_BnM();
        uint256 TGOLDRes = getReserveTGOLD();

        // i/p reserve is CCIP_BnM reserve, RIGHT before we transferred CCIP_BnM to the contract for swap
        // bcz Denominator of Golden Formlae is (x + Delta x) and 'x' is exclusive of 'Delta x' at this point
        uint256 amountTGOLD = getAmountOfTokens(       // 1% swap/trade fee taken care of in this f() above
            amountCCIP_BnM,
            CCIP_BnMRes,               // always TGOLD-balance SHOULD BE the one that's before amountTGOLD adds to the TGOLD's reserve
            TGOLDRes             
        );

        if(amountTGOLD < minTGOLD) {
            revert OutputAmountInsufficient();
        }
        // Transfer ERC20 amountCCIP_BnM to Exchange.sol (must already have been approved)
        IERC20(CCIP_BnMTokenAddress).transferFrom(_msgSender(), address(this), amountCCIP_BnM);
        // Transfer ERC20 amountTGOLD to the user
        
        // Transfer swapped asset ONLY AFTER revert checked + CCIP_BnM transferred to Exchange.sol
        IERC20(TGOLDTokenAddress).transfer(_msgSender(), amountTGOLD);
        // will NOT send minTGOLD as this does not 'obey' the Golden Formulae and will have price impact on our reserves
        emit SwappedCCIP_BnMToTGOLD(amountCCIP_BnM, amountTGOLD);   
    }

    // whitelisting features missing here
    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {

    }
    // ================================
    // GETTERS / Other Helper or internal functions

    /**
     * @dev returns the amount of Eth/TG tokens that are required to be returned to the user/trader upon swap
     * @param _amountTGOLD amount of TGOLD input
     * @param _amountCCIP_BnM amount of CCIP_BnM input
     * @return (optional)
     */
     function _addBothTokensInLP(IERC20 TGOLDToken, uint256 _amountTGOLD, IERC20 CCIP_BnMToken, uint256 _amountCCIP_BnM) internal returns (uint256, uint256) {
        // console.log("msg.sender: ", _msgSender());
        // first approve, then only transferFrom()
        // TGOLDToken.approve(address(this), _amountTGOLD);                
        // CCIP_BnMToken.approve(address(this), _amountCCIP_BnM);
        // avoid accessing msg.sender directly
        TGOLDToken.transferFrom(_msgSender(), address(this), _amountTGOLD);
        CCIP_BnMToken.transferFrom(_msgSender(), address(this), _amountCCIP_BnM);
        
        emit AddedLiquidty(_amountTGOLD, _amountCCIP_BnM);
        return (_amountTGOLD, _amountCCIP_BnM);
     }

    /**
     * @dev returns the amount of TG/CCIP_BnM tokens that are required to be returned to the user/trader upon swap
     */
    function getAmountOfTokens(
    uint256 inputAmount, 
    uint256 inputReserve, 
    uint256 outputReserve) 
    public pure returns (uint256) {
        if(inputReserve < 0 || outputReserve < 0) {
            revert InvalidReserveQuantity();
        }
        // We are charging a fee of `1%`
        // Input amount with fee = (input amount - (1*(input amount)/100)) = ((input amount)*99)/100
        // ===== uint256 inputAmountWithFee = (inputAmount*99)/100;
        // Because we need to follow the concept of `XY = K` curve
        // We need to make sure (x + Δx) * (y - Δy) = x * y
        // So the final formula is Δy = (y * Δx) / (x + Δx)
        // Δy in our case is `tokens to be received`
        // Δx = ((input amount)*99)/100, x = inputReserve, y = outputReserve
        // So by putting the values in the formulae you can get the numerator and denominator
        // =====uint256 numerator = outputReserve * inputAmountWithFee;
        // =====uint256 denominator = inputReserve + inputAmountWithFee;
        uint256 numerator = outputReserve * inputAmount;
        uint256 denominator = inputReserve + inputAmount;
        // console.log("inputAmount: ", inputAmount);
        // console.log("inputAmountWithFee: ", inputAmountWithFee);
        // console.log("numerator: ", numerator);
        // console.log("denominator: ", denominator);
        return numerator / denominator;
    }
   
   function getTGOLDTokenAddress() public view returns(address) {
       return TGOLDTokenAddress;
   }

   function getCCIP_BnMTokenAddress() public view returns(address) {
       return CCIP_BnMTokenAddress;
   }

   /**
    * @dev Returns the amount of `TGOLD Tokens` held by the Exchange.sol contract (not user)
    */
    function getReserveTGOLD() public view returns (uint256) {
        return IERC20(TGOLDTokenAddress).balanceOf(address(this));   // convention - IERC20(address).balaOf(address)
    }

    /**
    * @dev Returns the amount of `CCIP_BnM Tokens` held by the Exchange.sol contract (not user)
    */
    function getReserveCCIP_BnM() public view returns (uint256) {
        return IERC20(CCIP_BnMTokenAddress).balanceOf(address(this));   // convention - IERC20(address).balaOf(address)
    }

    
    fallback() external {}

    uint256 public contractBalance = address(this).balance;

}



