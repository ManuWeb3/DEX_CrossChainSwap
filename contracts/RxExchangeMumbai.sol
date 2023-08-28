// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract RxExchangeMumbai is Ownable {

    error AddressZeroError();
    error UnauthorizedCaller();

    event SwappedTGOLDToCCIP_BnM(uint256 amountCCIPBnM);

    address private immutable i_dummyCCIP_BnMMumbai;
    address private destContract;

    modifier onlyDestContract {
        if(_msgSender() != destContract) {
            revert UnauthorizedCaller();
        }
        _;
    }

    constructor(address _DummyCCIP_BnMMumbai) {
        if (_DummyCCIP_BnMMumbai == address(0)) {
            
            revert AddressZeroError();
        }
        i_dummyCCIP_BnMMumbai = _DummyCCIP_BnMMumbai;   // ERC20 token that mints() on Mumbai
    }

    function swapTGOLDToCCIP_BnM(address swapRxAddress, uint256 amountCCIP_BnM) external onlyDestContract {
        // transfer amountCCIP_BnM to EOA out of this.CCIP_BnM reserves
        ERC20(i_dummyCCIP_BnMMumbai).transfer(swapRxAddress, amountCCIP_BnM);
        emit SwappedTGOLDToCCIP_BnM(amountCCIP_BnM);
    }

    function setDestContract(address _destContract) external onlyOwner {
        destContract = _destContract;
    }

    function getReserveCCIP_BnM() public view returns (uint256) {
        return ERC20(i_dummyCCIP_BnMMumbai).balanceOf(address(this));   // convention - IERC20(address).balanceOf(address)
    }

    // the Destination Contract that will .call(calldata) the RxExchange.sol's swap()
    function getDestContractAddress() public view returns(address) {
       return destContract;
   }
}