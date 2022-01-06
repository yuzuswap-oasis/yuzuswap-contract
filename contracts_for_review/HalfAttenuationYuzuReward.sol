// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";




contract HalfAttenuationYuzuReward {
    using SafeMath for uint256;

    // The block number when YUZU mining starts
    uint256 immutable public startBlock;
    // The block number of half cycle
    uint256 immutable public  blockNumberOfHalfAttenuationCycle;
      // YUZU tokens created per block.
    uint256 immutable public yuzuPerBlock;


     constructor(
        uint256 _yuzuPerBlock,
        uint256 _startBlock,
        uint256 _blockNumberOfHalfAttenuationCycle
    ) public {
        yuzuPerBlock = _yuzuPerBlock;
        startBlock = _startBlock;
        blockNumberOfHalfAttenuationCycle = _blockNumberOfHalfAttenuationCycle;
    }

    // Return reward multiplier over the given _from to _to block.
    function getYuzuBetweenBlocks(uint256 _from, uint256 _to)
        public
        view
        returns (uint256)
    {
        return _getYuzuFromStartblock(startBlock,blockNumberOfHalfAttenuationCycle,yuzuPerBlock,_to).sub( _getYuzuFromStartblock(startBlock,blockNumberOfHalfAttenuationCycle,yuzuPerBlock,_from));
    }


    //for test
    function getYuzuFromStartblock(uint256 _startBlock,uint256 _blockNumberOfHalfAttenuationCycle, uint256 _yuzuPerBlock,uint256 _to)
        public
        pure
        returns (uint256)
    {
        return _getYuzuFromStartblock(_startBlock,_blockNumberOfHalfAttenuationCycle,_yuzuPerBlock,_to);
    }




    /* purpose: record the yuzu reward from startblock -> args{to} block
     * args : 
     * _startBlock reward started block
     * _blockNumberOfHalfAttenuationCycle  how many blocks to half the init reward
     * _yuzuPerBlock per block yuzu at first 
     * _to: until which block
     * returns: the amount of yuzu 
     */ 

    function _getYuzuFromStartblock(uint256 _startBlock,uint256 _blockNumberOfHalfAttenuationCycle,uint256 _yuzuPerBlock, uint256 _to)
        internal
        pure
        returns (uint256)
    {
        uint256 cycle = _to.sub(_startBlock).div(_blockNumberOfHalfAttenuationCycle);
        if(cycle > 255){
            cycle =  255;
        }
        uint256 attenuationMul =  1 << cycle;

        return _yuzuPerBlock.mul(_blockNumberOfHalfAttenuationCycle.mul(2)).sub(_yuzuPerBlock.mul(_blockNumberOfHalfAttenuationCycle).div(attenuationMul)).sub(    
            _blockNumberOfHalfAttenuationCycle.sub( _to.sub(_startBlock).mod(_blockNumberOfHalfAttenuationCycle) ).mul(_yuzuPerBlock).div(attenuationMul)
          );
    }




}

