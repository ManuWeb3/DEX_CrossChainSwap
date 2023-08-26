// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./Test.sol";

contract CallingTest2 is Test {
    
    bytes encodedCall;

    address test = 0x0fC5025C764cE34df352757e82f7B5c4Df39A836;

    Test testObj;

    function callingTestExternally() public {
        address(this).call(encodedCall);
    }

    function abiEncode() public  {
        encodedCall = abi.encodeWithSignature("sumVars()");
    }
}