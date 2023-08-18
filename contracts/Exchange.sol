// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Exchange is ERC20 {

    error SendFailed();
    error AddressZeroError();
    error InsufficientERC20Input();
    error InvalidReserveQuantity();
    error InputAmountNotGreaterThanZero();
    error OutputAmountLessThanMinimumAmount();
    // ERC20 is needed for a couple of things
    // 1. TG token is an ERC20 one
    // 2. input this address and check the balanceOf(thisContract)
    address public TGOLDTokenAddress;

    constructor (address _TGOLDToken) ERC20 ("TGOLD LP Token", "TGLP") {
        //require(_TGOLDToken != address(0), "Token address passed is a null address"); 
        if(_TGOLDToken == address(0)) {
            revert AddressZeroError();
        }
        TGOLDTokenAddress = _TGOLDToken;
    }
    
    /**
    * @dev Returns the amount of `TGOLD Tokens` held by the Exchange.sol contract (not user)
    */

    function getReserve() public view returns (uint256) {
        return ERC20(TGOLDTokenAddress).balanceOf(address(this));   // convention - IERC20(address).balaOf(address)
    }

    /**
    * @dev Adds liquidity to the exchange.
    */
   // i/p "_amount" refers to the TG Tokens being deplosited by the LP
   function addLiquidity(uint256 _amount) public payable returns (uint256) {
        uint256 liquidity;      // if() else() = TG LP tokens to be minted to LP
        uint256 ethBalance = address(this).balance;     // this includes sent amount with "payable" even at the first go
        // later on, addLiquidity(), ethReserve will differ from initial ethBalance
        uint256 TGOLDTokenReserve = getReserve();   // TG Reserve
        // instantiated an object of type ERC20 for a TGToken contract deployed at that address
        ERC20 TGOLDToken = ERC20(TGOLDTokenAddress);    // slightly diff. names/identifiers used elsewhere
        /*
        If the reserve is empty, intake any user supplied value for
        `Ether` and `TGOLD` tokens because there is no ratio currently
        */
       if(TGOLDTokenReserve == 0) {
        // Transfer the `TGOLDToken` from the user's account to the contract
        // transferFrom() will revert if approval not set
        // this will be set in a JS script as Patrick did in AAVE's DeFi project
        // not done anywhere min Solidity - REMEMBER this
        
        // WHY not add this here:
        TGOLDToken.approve(address(this), _amount);
        // avoid accessing msg.sender directly
        TGOLDToken.transferFrom(_msgSender(), address(this), _amount);
        // _amount is the TG token itself whose obj is created and initialized above to exec transferFrom()
        // as this is exactly how it's done in Remix's interface

        // `liquidity` provided is equal to `ethBalance` because this is the first time user
        // is adding `Eth` to the contract, so whatever `Eth` contract has is equal to the one supplied
        // by the user in the current `addLiquidity` call (payable)
        // `liquidity` tokens that need to be minted to the user on `addLiquidity` call should always be proportional
        // to the Eth specified by the user bcz Liquidity (amount of LP Tokens) = EthBalance
        // liquidity = "amount of LP tokens" (not full tokens, it'll be = wei)
        // bcz ETH internally works as wei with address(this).balance
        liquidity = ethBalance;
        // _msgSender() = LProvider here
        // _mint() will mint 'liquidity' amount of tokens...which ones... 
        // the ones created by the constructor during deployment (TGLP tokens)
        _mint(_msgSender(), liquidity);
       }
       else {
        /*
            If the reserve is not empty, intake any user supplied value for
            `Ether` and determine according to the ratio how many `TGOLD` tokens
            need to be supplied to prevent any large price impacts because of the additional
            liquidity
        */
        // EthReserve should be the current ethBalance subtracted by the value of ether sent by the user
        // in the current `addLiquidity` call
        // that's why, we already calculated ethBalance = address(this).bal
        // as it will be needed everytime the addLiq() execs
        // ethBal instantly takes in payable-ether transfered by user to the contract
        // in address(this).bal (not at the end of f() call)
        // ethReserve actually points to the value of eth stored in contract right before this txn ran by the user/LP
        // by sutracting msg.value
            uint256 ethReserve = ethBalance - msg.value;
         // Ratio should always be maintained so that there are no major price impacts when adding liquidity
         // Ratio here is 
         // -> (TGOLDTokenAmount user can add/TGOLDTokenReserve already in the contract) = (Eth Sent by the user/Eth Reserve already in the contract);
         // "already" = just before this txn gets mined
         // So doing some maths, (TGOLDTokenAmount user can add) = (Eth Sent by the user * TGOLDTokenReserve /Eth Reserve);

         // TGOLDTokenAmount- what an LP can deposit, IDEALLY, MINIMUM (>=) this should be the _amount else revert 
         // TGOLDTokenReserve - by getReserve();
         // THE GOLDEN RATIO HAS TO BE MAINTAINED
         uint256 TGOLDTokenAmount = (msg.value/ethReserve)*TGOLDTokenReserve; 
        // calculateTG() in addLiquidity.js of Front end

        // require(_amount >= TGOLDTokenAmount, "Amount of tokens sent is less than the minimum tokens required");
        if(_amount < TGOLDTokenAmount) {
            revert InsufficientERC20Input();
        }
        // transfer only (TGOLDTokenAmount user can add) amount of `TGOLD tokens` from users account
        // to the contract

        // INTERNAL TXN
        TGOLDToken.transferFrom(_msgSender(), address(this), TGOLDTokenAmount);
        // calc. liquidity = LP tokens to be minted to the LProvider thru _mint()
        // 2ND FACET OF THE GOLDEN RATION w.r.t TG LP tokens (liquidity)
        // totalSupply() increases in proportion to the (msg.value/ethReserve)
        liquidity = totalSupply() * (msg.value/ethReserve);
        // the golden ratio * _totalSupply of LP tokens out there in the open market held by LPs will be minted to the current LP
        
        _mint(_msgSender(), liquidity);
        // IMPORTANT:
        // the _mint() will anyway be coded after both (Eth + TG tokens) have been accepted by the contract
        // to avoid the situation when he already got the TG LP tokens and his eth+TG tokens are yet to be accepted by the contract
        }
        return liquidity;
        // returning uint256
   }

   /**
    * @dev Returns the amount Eth/TGOLD tokens that would be returned to the user
    * in the swap of TG LP tokens with user-funds
    */
   function removeLiquidity(uint _amount) public returns (uint , uint) {
    // require(_amount > 0, "_amount should be greater than zero");
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
    uint TGOLDTokenAmount = (getReserve() * _amount)/ _totalSupply;     // formulae # 2, TGOLDTokenAmount determined, later transfer
    
    // Burn the sent LP tokens from the user's wallet because they are already sent to
    // remove liquidity
    
    // IMPORTANT:
    // first _burn(), then .call{}() and .transfer() TG Tokens
    // first set the state, then transfer funds, per RE-ENTRANCY
    _burn(_msgSender(), _amount);         // burn(), as opposed to _mint()
    
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
     * @dev returns the amount of Eth/TG tokens that are required to be returned to the user/trader upon swap
     */
    function getAmountOfTokens(
    uint256 inputAmount, 
    uint256 inputReserve, 
    uint256 outputReserve) 
    public pure returns (uint256) {
        // require(inputReserve>0 && outputReserve > 0, "Invalid reserves");
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
    
    /**
    * @dev Swaps Eth for TGOLD Tokens
    * payable bcz we're accepting Ether in the contract for swapping with TG Tokens
    * to buy _minTokens when selling (payable) Eth
    */

   // _minTokens sort of expectation, is what user wants / expects
   function ethToTGOLDTokens(uint256 _minTokens) public payable {
    uint256 tokenReserve = getReserve();
    // i/p reserve is Eth reserve, RIGHT before we transferred Eth to the contract for swap
    // bcz it's (x + Delta x) and 'x' is exclusive of 'Delta x' at this point
    // hence, (available balance - msg.value)
    uint256 tokensBought = getAmountOfTokens(       // 1% swap/trade fee taken care of in this f() above
        msg.value,
        address(this).balance - msg.value,          // always Eth-balance SHOULD BE the one that's before msg.value adds to the EthReserve
        tokenReserve            // no input of TG Tokens, hence getReserve() already returns amount of TG Tokens without any new input considered
    );
    // require(tokensBought >= _minTokens, "Insufficient output amount, as per what you expect");
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
        getReserve(),               // no need to subtract any token amount as it does not gets auot-added unlike paybale-Eth
        address(this).balance       // no "payable" this time. Hence, reserve is the same, no need to subtract msg.value
    );

    // require(ethBought >= _minEth, "Insufficient output amount, as per what you expect");
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
    //require(success, "Eth Transfer Failed");
    if (!success) {
        revert SendFailed();
    }
   }    
}