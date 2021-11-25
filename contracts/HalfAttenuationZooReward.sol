// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";




contract HalfAttenuationZooReward {
    using SafeMath for uint256;

    // The block number when ZOO mining starts
    uint256 public startBlock;
    // The block number of half cycle
    uint256 public  blockNumberOfHalfAttenuationCycle;
      // ZOO tokens created per block.
    uint256 public zooPerBlock;


     constructor(
        uint256 _zooPerBlock,
        uint256 _startBlock,
        uint256 _blockNumberOfHalfAttenuationCycle
    ) public {
        zooPerBlock = _zooPerBlock;
        startBlock = _startBlock;
        blockNumberOfHalfAttenuationCycle = _blockNumberOfHalfAttenuationCycle;
    }

    // Return reward multiplier over the given _from to _to block.
    function getZooBetweenBlocks(uint256 _from, uint256 _to)
        public
        view
        returns (uint256)
    {
        return _getZooFromStartblock(startBlock,blockNumberOfHalfAttenuationCycle,zooPerBlock,_to).sub( _getZooFromStartblock(startBlock,blockNumberOfHalfAttenuationCycle,zooPerBlock,_from));
    }


    //for test
    function getZooFromStartblock(uint256 _startBlock,uint256 _blockNumberOfHalfAttenuationCycle, uint256 _zooPerBlock,uint256 _to)
        public
        view
        returns (uint256)
    {
        return _getZooFromStartblock(_startBlock,_blockNumberOfHalfAttenuationCycle,_zooPerBlock,_to);
    }



    function _getZooFromStartblock(uint256 _startBlock,uint256 _blockNumberOfHalfAttenuationCycle,uint256 _zooPerBlock, uint256 _to)
        internal
        pure
        returns (uint256)
    {
        uint256 cycle = _to.sub(_startBlock).div(_blockNumberOfHalfAttenuationCycle);
        if(cycle > 255){
            cycle =  255;
        }
        uint256 attenuationMul =  1 << cycle;

        return _zooPerBlock.mul(_blockNumberOfHalfAttenuationCycle.mul(2)).sub(_zooPerBlock.mul(_blockNumberOfHalfAttenuationCycle).div(attenuationMul)).sub(    
            _blockNumberOfHalfAttenuationCycle.sub( _to.sub(_startBlock).mod(_blockNumberOfHalfAttenuationCycle) ).mul(_zooPerBlock).div(attenuationMul)
          );
    }




}

