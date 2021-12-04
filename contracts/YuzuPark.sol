// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./YuzuToken.sol";
import "./HalfAttenuationYuzuReward.sol";




interface IYuzuKeeper {
  //Yuzukeeper is in charge of the yuzu
  //It control the speed of YUZU release by rules 
  function requestForYUZU(uint256 amount) external returns (uint256);

  //ask the actual yuzu  Got ( should minus some yuzu of devs and inverstors)
  function queryActualYUZUReward(uint256 amount) external view returns (uint256);
}


// YuzuPark is interesting place where you can get more Yuzu as long as you stake
// Have fun reading it. Hopefully it's bug-free. God bless.

contract YuzuPark is Ownable ,HalfAttenuationYuzuReward,ReentrancyGuard{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using SafeERC20 for YUZUToken;
    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of Zos
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accYuzuPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accYuzuPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }
    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. YUZUs to distribute per block.
        uint256 lastRewardBlock; // Last block number that YUZUs distribution occurs.
        uint256 accYuzuPerShare; // Accumulated YUZUs per share, times 1e12. See below.
    }
    // The Yuzu TOKEN!
    YUZUToken public yuzu;
    // The Yuzu Keeper
    IYuzuKeeper public yuzukeeper;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    constructor(
        YUZUToken _yuzu,
        IYuzuKeeper _yuzukeeper,
        uint256 _yuzuPerBlock,
        uint256 _startBlock,
        uint256 _blockNumberOfHalfAttenuationCycle
    ) public HalfAttenuationYuzuReward(_yuzuPerBlock,_startBlock,_blockNumberOfHalfAttenuationCycle){
        require(address(_yuzu) != address(0));
        require(address(_yuzukeeper) != address(0));

        yuzu = _yuzu;
        yuzukeeper = _yuzukeeper;
        yuzuPerBlock = _yuzuPerBlock;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken
    ) public onlyOwner {
        bool _withUpdate = true;//force to true in case of security risks
        if (_withUpdate) {
            massUpdatePools();
        }
        duplicatedTokenDetect(_lpToken);

        uint256 lastRewardBlock =
            block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accYuzuPerShare: 0
            })
        );
    }

    // Update the given pool's YUZU allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint
    ) public onlyOwner {
        bool _withUpdate = true;//force to true in case of security risks
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
    }


    // View function to see pending YUZUs on frontend.
    function pendingYuzu(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accYuzuPerShare = pool.accYuzuPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 yuzuReward =
                getYuzuBetweenBlocks(pool.lastRewardBlock, block.number).mul(pool.allocPoint).div(
                    totalAllocPoint
                );
            yuzuReward = yuzukeeper.queryActualYUZUReward(yuzuReward);
            accYuzuPerShare = accYuzuPerShare.add(
                yuzuReward.mul(1e12).div(lpSupply)
            );
        }
        return user.amount.mul(accYuzuPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward vairables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 yuzuReward = getYuzuBetweenBlocks(pool.lastRewardBlock, block.number).mul(pool.allocPoint).div(
                totalAllocPoint
            );

        yuzuReward = yuzukeeper.requestForYUZU(yuzuReward);

        pool.accYuzuPerShare = pool.accYuzuPerShare.add(
            yuzuReward.mul(1e12).div(lpSupply)
        );
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to YuzuPark for Yuzu allocation.
    function deposit(uint256 _pid, uint256 _amount) public nonReentrant{
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending =
                user.amount.mul(pool.accYuzuPerShare).div(1e12).sub(
                    user.rewardDebt
                );
            safeYuzuTransfer(msg.sender, pending);
        }
        //Incompatibility with Deflationary Tokens
        uint256 lpBalanceBeforeDeposit = pool.lpToken.balanceOf(address(this));
        pool.lpToken.safeTransferFrom(
            address(msg.sender),
            address(this),
            _amount
        );
        uint256 lpBalanceAfterDeposit = pool.lpToken.balanceOf(address(this));
        uint256 realDepositAmount = lpBalanceAfterDeposit.sub(lpBalanceBeforeDeposit);

        user.amount = user.amount.add(realDepositAmount);
        user.rewardDebt = user.amount.mul(pool.accYuzuPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, realDepositAmount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant{
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending =
            user.amount.mul(pool.accYuzuPerShare).div(1e12).sub(
                user.rewardDebt
            );
        safeYuzuTransfer(msg.sender, pending);
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accYuzuPerShare).div(1e12);
        pool.lpToken.safeTransfer(address(msg.sender), _amount);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public nonReentrant{
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Safe yuzu transfer function, just in case if rounding error causes pool to not have enough YUZUs.
    function safeYuzuTransfer(address _to, uint256 _amount) internal {
        uint256 yuzuBal = yuzu.balanceOf(address(this));
        if (_amount > yuzuBal) {
            yuzu.safeTransfer(_to, yuzuBal);
        } else {
            yuzu.safeTransfer(_to, _amount);
        }
    }


    function duplicatedTokenDetect ( IERC20 _lpToken ) internal view{
        uint256 length = poolInfo.length ;
        for ( uint256 pid = 0; pid < length ; ++ pid) {
            require(poolInfo[pid].lpToken != _lpToken , "add: duplicated token");
        }
    }

}
