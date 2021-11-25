// SPDX-License-Identifier: MIT



import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import './uniswapv2/libraries/UniswapV2Library.sol';
import "./YuzuToken.sol";
import "./YuzuRouter.sol";
import "./HalfAttenuationYuzuReward.sol";


interface IYuzuKeeper {
  //Yuzukeeper is in charge of the yuzu
  //It control the speed of YUZU release by rules 
  function requestForYUZU(uint256 amount) external returns (uint256);

  //ask the actual yuzu  Got ( should minus some yuzu of devs and inverstors)
  function queryActualYUZUReward(uint256 amount) external view returns (uint256);
}


// YuzuSwapMining is interesting place where you can get more YUZU as long as you stake
// Have fun reading it. Hopefully it's bug-free. God bless.

contract YuzuSwapMining is Ownable ,HalfAttenuationYuzuReward,ReentrancyGuard{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
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
        address lpToken; // Address of LP token contract.
        address archorTokenAddr; //the anchor token for swap weight
        uint256 lpTokenTotal;
        uint256 allocPoint; // How many allocation points assigned to this pool. YUZUs to distribute per block.
        uint256 lastRewardBlock; // Last block number that YUZUs distribution occurs.
        uint256 accYuzuPerShare; // Accumulated YUZUs per share, times 1e12. See below.
    }

    // The YUZU TOKEN!
    YuzuToken public yuzu;
    //The YUZURouter addr
    address public routerAddr;
    address public factoryAddr;
    // The YUZU Keeper
    IYuzuKeeper public yuzukeeper;
  
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;

    //Pos start from 1, pos-1 equals pool index 
    mapping(address => uint256) public tokenPairMapPoolPos;



    event MinedBySwap(address indexed user, uint256 indexed pid, uint256 yuzuAmount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 lpBurned,uint256 yuzuAmount);

    modifier onlyRouter() {
        require(msg.sender == routerAddr, "YuzuSwapMining: sender isn't the router");
        _;
    }


    constructor(
        YuzuToken _yuzu,
        IYuzuKeeper _yuzukeeper,
        address payable _routerAddr,
        uint256 _yuzuPerBlock,
        uint256 _startBlock,
        uint256 _blockNumberOfHalfAttenuationCycle
    ) public HalfAttenuationYuzuReward(_yuzuPerBlock,_startBlock,_blockNumberOfHalfAttenuationCycle) {
        require(address(_yuzu) != address(0));
        require(address(_yuzukeeper) != address(0));
        require(_routerAddr != address(0));
        yuzu = _yuzu;
        yuzukeeper = _yuzukeeper;
        routerAddr = _routerAddr;
        factoryAddr = YuzuRouter(_routerAddr).factory();
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }


    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(
        uint256 _allocPoint,
        address _archorTokenAddr,
        address _anotherTokenAddr,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        address _lpToken = UniswapV2Library.pairFor(factoryAddr, _archorTokenAddr, _anotherTokenAddr);
        uint256 lastRewardBlock =
            block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                archorTokenAddr:_archorTokenAddr,
                lpTokenTotal : 0, 
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accYuzuPerShare: 0
            })
        );
        tokenPairMapPoolPos[_lpToken] =  poolInfo.length;
    }

    // Update the given pool's YUZU allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
    }


    // View function to see pending YUZUs on frontend.
    function pendingYuzuAll(address _user)
        external
        view
        returns (uint256)
    {
        uint256 total = 0;
        uint256 length = poolInfo.length;
        for (uint256 _pid = 0; _pid < length; ++_pid) {
            PoolInfo storage pool = poolInfo[_pid];
            UserInfo storage user = userInfo[_pid][_user];
            uint256 accYuzuPerShare = pool.accYuzuPerShare;
            uint256 lpSupply = pool.lpTokenTotal;
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
            total = user.amount.mul(accYuzuPerShare).div(1e12).sub(user.rewardDebt).add(total);
        }
        return total;
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
        uint256 lpSupply = pool.lpTokenTotal;
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
        uint256 lpSupply = pool.lpTokenTotal;
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 yuzuReward =
            getYuzuBetweenBlocks(pool.lastRewardBlock, block.number).mul(pool.allocPoint).div(
            totalAllocPoint);

        yuzuReward = yuzukeeper.requestForYUZU(yuzuReward);


        pool.accYuzuPerShare = pool.accYuzuPerShare.add(
            yuzuReward.mul(1e12).div(lpSupply)
        );
        pool.lastRewardBlock = block.number;
    }

    function withdrawAll() public nonReentrant{
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            uint256 liqBalance = userInfo[pid][msg.sender].amount; 
            _withdraw(pid, liqBalance);
        }
    }

    function withdraw(uint256 _pid) public nonReentrant{
        uint256 liqBalance = userInfo[_pid][msg.sender].amount; 
        _withdraw(_pid, liqBalance);
    }

    function swap(address account, address input, address output, uint256 inAmount  ,uint256 outAmount) onlyRouter external returns (bool){
        address pair = UniswapV2Library.pairFor(factoryAddr, input, output);
        // no error if pair not set 
        if (tokenPairMapPoolPos[ pair ] == 0 ){
            return true;
        }
        uint256 _pid = tokenPairMapPoolPos[ pair ].sub(1);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][account];
        updatePool(_pid);
        uint256 _amount;
        if( pool.archorTokenAddr == input ){
            _amount = inAmount;
        }else{
            _amount = outAmount;
        }

        pool.lpTokenTotal = pool.lpTokenTotal.add(_amount);
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.rewardDebt.add(_amount.mul(pool.accYuzuPerShare).div(1e12));

        emit MinedBySwap(account, _pid, _amount);
        return true;
    }


    // Safe yuzu transfer function, just in case if rounding error causes pool to not have enough YUZUs.
    function safeYuzuTransfer(address _to, uint256 _amount) internal {
        uint256 yuzuBal = yuzu.balanceOf(address(this));
        if (_amount > yuzuBal) {
            yuzu.transfer(_to, yuzuBal);
        } else {
            yuzu.transfer(_to, _amount);
        }
    }

    function _withdraw(uint256 _pid,uint256 _burned) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _burned, "withdraw: not good");

        updatePool(_pid);
        uint256 pending =
            user.amount.mul(pool.accYuzuPerShare).div(1e12).sub(
                user.rewardDebt
            );
        safeYuzuTransfer(msg.sender, pending);
        //burn all lp
        pool.lpTokenTotal = pool.lpTokenTotal.sub(_burned);
        user.amount = user.amount.sub(_burned);

        user.rewardDebt = user.amount.mul(pool.accYuzuPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid,_burned, pending);
    }


}