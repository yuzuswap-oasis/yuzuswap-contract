// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./uniswapv2/UniswapV2Router02.sol";


interface ISwapMining {
    function swap(address account, address input, address output, uint256 inAmount,uint256 outAmount) external returns (bool);
}

contract SwapMiningMock {

    mapping(address => mapping(address => uint256)) public recorder;

    function swap(address account, address input, address output,uint256 inAmount, uint256 outAmount) external returns (bool)
    {
        recorder[account][output] += outAmount;
        return true;
    }

    function balance(address account,address token) external view returns (uint256) 
    {
        return recorder[account][token];
    }


}

contract YuzuRouter is UniswapV2Router02 ,Ownable{

    ISwapMining public swapMining;

    constructor(address _factory, address _WETH) UniswapV2Router02(_factory,_WETH) public {}

    function setSwapMining(ISwapMining _swapMininng) public onlyOwner {
        swapMining = _swapMininng;
    }

    function pairFor(address factory, address tokenA, address tokenB) public pure returns (address pair) {
        return UniswapV2Library.pairFor(factory ,tokenA,tokenB);
    }

  // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint[] memory amounts, address[] memory path, address _to) internal virtual override {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = UniswapV2Library.sortTokens(input, output);
            uint amountOut = amounts[i + 1];
            if (address(swapMining) != address(0)) {
                ISwapMining(swapMining).swap(msg.sender, input, output, amounts[i], amountOut);
            }

            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? UniswapV2Library.pairFor(factory, output, path[i + 2]) : _to;
            IUniswapV2Pair(UniswapV2Library.pairFor(factory, input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }
  // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to)  internal virtual override{
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = UniswapV2Library.sortTokens(input, output);
            IUniswapV2Pair pair = IUniswapV2Pair(UniswapV2Library.pairFor(factory, input, output));
            uint amountInput;
            uint amountOutput;
            { // scope to avoid stack too deep errors
            (uint reserve0, uint reserve1,) = pair.getReserves();
            (uint reserveInput, uint reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
            amountInput = IERC20Uniswap(input).balanceOf(address(pair)).sub(reserveInput);
            amountOutput = UniswapV2Library.getAmountOut(amountInput, reserveInput, reserveOutput);
            }

            if (address(swapMining) != address(0)) {
                ISwapMining(swapMining).swap(msg.sender, input, output,amountInput, amountOutput);
            }

            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
            address to = i < path.length - 2 ? UniswapV2Library.pairFor(factory, output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

}