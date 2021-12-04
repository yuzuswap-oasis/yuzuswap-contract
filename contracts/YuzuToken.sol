// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


// YuzuToken
contract YUZUToken is ERC20("YUZUToken", "YUZU"), Ownable {

  uint256 constant TOTAL_SUPPLAY =  (5*10 ** 8) * (10 ** 18) ;  // 500 milli

  // mint with max supply
  // no error if over max supply , just return false
  function mint(address _to, uint256 _amount) public onlyOwner returns (bool) {
      if (_amount.add(totalSupply()) > TOTAL_SUPPLAY) {
          return false;
      }
      _mint(_to, _amount);
      return true;
  }

}
