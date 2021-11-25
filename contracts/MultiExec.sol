// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

contract MultiExec {
    struct Call {
        address to;
        uint256 value;
        bytes data;
    }

    //For test
//    event Excuted(address to, bytes data);

    address public owner;
    modifier onlyOwner() {
        require(msg.sender == owner, "Ownable: caller is not the owner");
        _;
    }



    constructor () public {
        owner = msg.sender;
    }

    receive () external payable { }

    function exec(Call[] memory calls) public onlyOwner 
    {
        for (uint i = 0; i < calls.length; i++) {
            (bool success, ) = calls[i].to.call{value:calls[i].value}(calls[i].data);
            require(success, "call failed");
        }
    }
}