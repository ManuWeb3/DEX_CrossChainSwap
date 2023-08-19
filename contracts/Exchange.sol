// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "hardhat/console.sol";

/**
@title
@notice
@dev
*/

/// All the frontend scripts also get changed with the new token-pair here

contract Exchange is ERC20 {

    error SendFailed();
    error AddressZeroError();
    error InsufficientERC20Input();
    error InvalidReserveQuantity();
    error InputAmountNotGreaterThanZero();
    error OutputAmountLessThanMinimumAmount();

    event AddedLiquiidty(uint256, uint256);
    event RemovedLiquidity();
    event MintedLPTokens();
    event BunrtLPTokens();
    event SwappedTGOLDToCCIP_BnM();
    event SwappedCCIP_BnMToTGOLD();
    // ERC20 is needed for a couple of things
    // 1. TG token is an ERC20 one
    // 2. input this address and check the balanceOf(thisContract)
    address private TGOLDTokenAddress;
    address private CCIP_BnMTokenAddress;

    constructor (address _TGOLDToken, address _CCIP_BnMTokenAddress) ERC20 ("TGOLD LP Token", "TGLP") {
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
        
        // STEP # 3: _mint() will mint 'liquidity' amount of tokens...which ones... 
        // the ones created by the constructor during deployment of Exchange.sol (TGLP tokens)
        // NOT any other ERC20s like TGOLD/CCIP_BnM (external ERC20 contracts)
        _mint(_msgSender(), liquidity);
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
         uint256 CCIP_BnMTokenAmount = (_amountTGOLD/TGOLDReserve) * CCIP_BnMReserve; // exact Golden Ratio for Liquidity calc.
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
        liquidity = (_amountTGOLD/TGOLDReserve) * totalSupply();
        // (the golden ratio) * _totalSupply ( _totalSupply = private state var of inherited ERC20)...
        // Is LP tokens out there in the open market held by LPs, will be minted to the current LP
        // cannot use "getReserveTGOLD()" in place of TGOLDReserve in liquidity calc. above @ 144
        // as getReserveTGOLD() returns reserve value that NOW includes the newly added TGOLDTokenAmount via _addBothTokensInLP()
        
        // STEP # 3: _mint() applies only to TGLP token contract
        _mint(_msgSender(), liquidity);
        // IMPORTANT:
        // the _mint() will anyway be coded after both (TGOLD + CCIPBnM tokens) have been accepted by Exchange.sol
        // to avoid the situation when user already got the TG LP tokens before its TGOLD+CCIP_BnM tokens are accepted by Exchange.sol
        }
        return liquidity;
        // returning uint256
   }

   /**
    * @dev Returns the amount Eth/TGOLD tokens that would be returned to the user
    * in the swap of TG LP tokens with user-funds
    */
   function removeLiquidity(uint _amount) public returns (uint , uint) {
    if(_amount <=0) {
        revert InputAmountNotGreaterThanZero();
    }

    uint ethReserve = address(this).balance;        // current ETH reserve
    uint _totalSupply = totalSupply();              // current TG LP tokens reserve
    // The amount of Eth that would be sent back to the user is based
    // on a ratio
    // Ratio is -> (Eth sent back to the user) / (current Eth reserve)
    // = (amount of LP tokens that user wants to withdraw) / (total supply of LP tokens)
    // Then by same maths -> (Eth sent back to the user)
    // = (current Eth reserve * amount of LP tokens that user wants to withdraw) / (total supply of LP tokens)
    uint ethAmount = (ethReserve * _amount)/ _totalSupply;      // formulae # 1, ETH determined, later transfer
    // The amount of TGOLD token that would be sent back to the user is based
    // on a ratio
    // Ratio is -> (TGOLD sent back to the user) / (current TGOLD token reserve)
    // = (amount of LP tokens that user wants to withdraw) / (total supply of LP tokens)
    // Then by some maths -> (TGOLD sent back to the user)
    // = (current TGOLD token reserve * amount of LP tokens that user wants to withdraw) / (total supply of LP tokens)
    uint TGOLDTokenAmount = (getReserveTGOLD() * _amount)/ _totalSupply;     // formulae # 2, TGOLDTokenAmount determined, later transfer
    
    // Burn the sent LP tokens from the user's wallet because they are already sent to
    // remove liquidity
    
    // IMPORTANT:
    // first _burn(), then .call{}() and .transfer() TG Tokens
    // first set the state, then transfer funds, per RE-ENTRANCY
    _burn(_msgSender(), _amount);         // burn(), as opposed to _mint()
    // _burn() applies only to TGLP token contract

    //---------------------------
    // TRANSFER # 1: (ETH != ERC20 token, hence .call{}() used)
    // Transfer `ethAmount` of Eth from the contract to the user's wallet
    // instead, use userAddress.call{}("")
    
    (bool success, ) = _msgSender().call{value: ethAmount}("");       // instead of payable(_msgSender()).transfer(ethAmount);
    if (!success) {
        revert SendFailed();
    }

    // TRANSFER # 2: (ERC20 token != ETH, hence, use a f() of ERC20 token std.)
    // Transfer `TGOLDTokenAmount` of TGOLD tokens from the contract to the user's wallet
    // .transfer's _msgSender() is the contract itself (sender/from)
    // "_msgSender()" below is the user/to who invoked the f() removeLiq()
    
    // that's how we coded to send ERC20 tokens from inside a contract to an EOA
    ERC20(TGOLDTokenAddress).transfer(_msgSender(), TGOLDTokenAmount);
    //---------------------------

    return (ethAmount, TGOLDTokenAmount);
    }

    /**
    * @dev Swaps Eth for TGOLD Tokens
    * payable bcz we're accepting Ether in the contract for swapping with TG Tokens
    * to buy _minTokens when selling (payable) Eth
    */

   // _minTokens sort of expectation, is what user wants / expects
   function ethToTGOLDTokens(uint256 _minTokens) public payable {
    uint256 tokenReserve = getReserveTGOLD();
    // i/p reserve is Eth reserve, RIGHT before we transferred Eth to the contract for swap
    // bcz it's (x + Delta x) and 'x' is exclusive of 'Delta x' at this point
    // hence, (available balance - msg.value)
    uint256 tokensBought = getAmountOfTokens(       // 1% swap/trade fee taken care of in this f() above
        msg.value,
        address(this).balance - msg.value,          // always Eth-balance SHOULD BE the one that's before msg.value adds to the EthReserve
        tokenReserve            // no input of TG Tokens, hence getReserve() already returns amount of TG Tokens without any new input considered
    );
    if(tokensBought < _minTokens) {
        revert OutputAmountLessThanMinimumAmount();
    }
    // Transfer ERC20 tokensBought to the user
    // when we did not create a specific interface for .transfer/From() in this contract
    // and we can use ERC20 directly as we're inheriting OZ's ERC20
    ERC20(TGOLDTokenAddress).transfer(_msgSender(), tokensBought);
   }

   /**
    * @dev Swaps TGOLD Tokens for Eth
    * to buy _minEth when selling _tokensSold
    * no payable this time, ERC20 token amount will be one of the 2 parameters of this function
    */

   // _minEth sort of expectation
   function TGOLDTokensToEth(uint256 _tokensSold, uint256 _minEth) public {
    //uint256 tokenReserve = getReserve();
    uint256 ethBought = getAmountOfTokens(          // 1% swap/trade fee taken care of in this f() above
        _tokensSold,
        getReserveTGOLD(),               // no need to subtract any token amount as it does not gets auot-added unlike paybale-Eth
        address(this).balance       // no "payable" this time. Hence, reserve is the same, no need to subtract msg.value
    );

    if(ethBought < _minEth) {
        revert OutputAmountLessThanMinimumAmount();
    }
    // ADDITIONAL STEP OF TRANSFERFROM () IN THIS SWAP
    // the contract should trasnferFrom() _tokensSold first from the user's balance of TG tokens
    // to itself (basically, ERC20 mapping's updated)
    // Post-approval, of course in JS script
    // then, send the ethBought to the user, once all checks and balances are in place, coded above
    // FRIST GET ERC20, THEN ONLY SEND ETH
    ERC20(TGOLDTokenAddress).approve(address(this), _tokensSold);

    ERC20(TGOLDTokenAddress).transferFrom(_msgSender(), address(this), _tokensSold);

    // now, once the contract has ERC20 TG tokens, .call{EthBought}
    (bool success, ) = _msgSender().call{value: ethBought}("");
    if (!success) {
        revert SendFailed();
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
     function _addBothTokensInLP(IERC20 TGOLDToken, uint256 _amountTGOLD, IERC20 CCIP_BnMToken, uint256 _amountCCIP_BnM) internal returns (uint256, uint256) {
        TGOLDToken.approve(address(this), _amountTGOLD);
        // avoid accessing msg.sender directly
        TGOLDToken.transferFrom(_msgSender(), address(this), _amountTGOLD);
        
        // Adding CCIP_BnM to LP
        CCIP_BnMToken.approve(address(this), _amountCCIP_BnM);
        // avoid accessing msg.sender directly
        CCIP_BnMToken.transferFrom(_msgSender(), address(this), _amountCCIP_BnM);
     }

    /**
     * @dev returns the amount of Eth/TG tokens that are required to be returned to the user/trader upon swap
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
        uint256 inputAmountWithFee = (inputAmount*99)/100;
        // Because we need to follow the concept of `XY = K` curve
        // We need to make sure (x + Δx) * (y - Δy) = x * y
        // So the final formula is Δy = (y * Δx) / (x + Δx)
        // Δy in our case is `tokens to be received`
        // Δx = ((input amount)*99)/100, x = inputReserve, y = outputReserve
        // So by putting the values in the formulae you can get the numerator and denominator
        uint256 numerator = outputReserve * inputAmountWithFee;
        uint256 denominator = inputReserve + inputAmountWithFee;

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
        return ERC20(TGOLDTokenAddress).balanceOf(address(this));   // convention - IERC20(address).balaOf(address)
    }

    /**
    * @dev Returns the amount of `CCIP_BnM Tokens` held by the Exchange.sol contract (not user)
    */
    function getReserveCCIP_BnM() public view returns (uint256) {
        return ERC20(CCIP_BnMTokenAddress).balanceOf(address(this));   // convention - IERC20(address).balaOf(address)
    }
}