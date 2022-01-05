// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./YuzuToken.sol";
import "./YuzuPark.sol";
import "./HalfAttenuationYuzuReward.sol";



interface IRewarder {
    function onYUZUReward(uint256 _pid, address _user, uint256 _newLpAmount,uint256 _pendingYUZU) external;
    function pendingToken(uint256 _pid, address _user,uint256 _pendingYUZU) external view returns (IERC20 token,uint256 pending);
}

interface IMasterPark {
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. SUSHI to distribute per block.
        uint256 lastRewardBlock;  // Last block number that SUSHI distribution occurs.
        uint256 accYuzuPerShare; // Accumulated YUZUs per share, times 1e12. See below.
    }
 
    function poolInfo(uint256 pid) external view returns (IMasterPark.PoolInfo memory);
    function totalAllocPoint() external view returns (uint256);
    function deposit(uint256 _pid, uint256 _amount) external;
    function yuzuPerBlock() external view returns(uint256);
    function startBlock() external view returns(uint256);
    function blockNumberOfHalfAttenuationCycle() external view returns(uint256);
}

/// @notice The (older) YuzuPark contract gives out a constant number of Yuzu tokens per block.
/// The idea for this YuzuParkExt contract is therefore to be the owner of a dummy token
/// that is deposited into the YuzuPark contract.
/// The allocation point for this pool on MCV1 is the total allocation point for all pools that receive double incentives.

contract YuzuParkExt is Ownable ,HalfAttenuationYuzuReward, ReentrancyGuard{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using SafeERC20 for YUZUToken;
    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt
    }
    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;
        uint256 allocPoint; // How many allocation points assigned to this pool. YUZUs to distribute per block.
        uint256 lastRewardBlock; // Last block number that YUZUs distribution occurs.
        uint256 accYuzuPerShare; // Accumulated YUZUs per share, times 1e12. See below.
        IRewarder[] rewarders;
    }
    // Info of each pool.
    PoolInfo[] public poolInfo;
//    IRewarder[] public rewarders;

    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;

    uint256 private constant ACC_YUZU_PRECISION = 1e12;
    IMasterPark public immutable MASTER_PARK;
    uint256 public immutable MASTER_PID;
    YUZUToken public immutable yuzu;
    IYuzuKeeper public immutable yuzukeeper;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    constructor(
        YUZUToken _yuzu,
        IMasterPark _yuzupark,
        IYuzuKeeper _yuzukeeper,
        uint256 _masterPid
    ) public HalfAttenuationYuzuReward(_yuzupark.yuzuPerBlock(),_yuzupark.startBlock(),_yuzupark.blockNumberOfHalfAttenuationCycle()) {
        require(address(_yuzu) != address(0));
        require(address(_yuzupark) != address(0));
        require(address(_yuzukeeper) != address(0));
        yuzu = _yuzu;
        yuzukeeper=_yuzukeeper;
        MASTER_PARK = _yuzupark;
        MASTER_PID = _masterPid;
    }

   function init(IERC20 dummyToken) public onlyOwner  {
        uint256 balance = dummyToken.balanceOf(msg.sender);
        require(balance != 0, "YuzuParkExt: Balance must exceed 0");
        dummyToken.safeTransferFrom(msg.sender, address(this), balance);
        dummyToken.approve(address(MASTER_PARK), balance);
        MASTER_PARK.deposit(MASTER_PID, balance);
    }


    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function poolRewarders(uint256 _pid) external view returns (IRewarder[] memory) {
        return poolInfo[_pid].rewarders;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    // TODO: decide whether to massUpdate
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        IRewarder[] memory _rewarders
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
                accYuzuPerShare: 0,
                rewarders : _rewarders 
            })
        );
    }

    // Update the given pool's YUZU allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        IRewarder[] memory _rewarders,
        bool overwrite
    ) public onlyOwner {
        bool _withUpdate = true;//force to true in case of security risks
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        if (overwrite) { poolInfo[_pid].rewarders = _rewarders; }
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
                _getMasterYuzuBetweenBlocks(pool.lastRewardBlock, block.number).mul(pool.allocPoint).div(
                    totalAllocPoint
                );
            yuzuReward = yuzukeeper.queryActualYUZUReward(yuzuReward);
            accYuzuPerShare = accYuzuPerShare.add(
                yuzuReward.mul(1e12).div(lpSupply)
            );
        }
        return user.amount.mul(accYuzuPerShare).div(1e12).sub(user.rewardDebt);
    }


  	function pendingTokens(
		uint256 pid,
		address user
	) external view  returns (IERC20[] memory rewardTokens, uint256[] memory rewardAmounts) {
        uint256 _pendingYUZU = this.pendingYuzu(pid,user);
        PoolInfo memory pool = poolInfo[pid];
        uint rewardLen = pool.rewarders.length;
		IERC20[] memory _rewardTokens = new IERC20[](rewardLen);
		uint256[] memory _rewardAmounts = new uint256[](rewardLen);
        for(uint i=0;i < rewardLen ; i++){
             IRewarder reward =  pool.rewarders[i];
             (IERC20 rewardToken,uint256 pendingReward) = reward.pendingToken(pid, user,_pendingYUZU);
             _rewardTokens[i] = rewardToken;
            _rewardAmounts[i] = pendingReward;
        }

		return (_rewardTokens, _rewardAmounts);
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
        uint256 yuzuReward = _getMasterYuzuBetweenBlocks(pool.lastRewardBlock, block.number).mul(pool.allocPoint).div(
                totalAllocPoint
            );

        yuzuReward = yuzukeeper.queryActualYUZUReward(yuzuReward);

        pool.accYuzuPerShare = pool.accYuzuPerShare.add(
            yuzuReward.mul(1e12).div(lpSupply)
        );
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to YuzuPark for Yuzu allocation.
    function deposit(uint256 _pid, uint256 _amount) public nonReentrant{
        harvestFromMasterPark();
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        uint256 pending = 0;
        if (user.amount > 0) {
                pending = user.amount.mul(pool.accYuzuPerShare).div(1e12).sub(
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

        IRewarder[] memory _rewarders  = poolInfo[_pid].rewarders;
        for(uint256 i = 0;i < _rewarders.length ; i ++ ){
            IRewarder _rewarder = _rewarders[i];
            if(address(_rewarder) != address(0)){
                _rewarder.onYUZUReward(_pid,msg.sender, user.amount,pending);
            }
        }
        

        emit Deposit(msg.sender, _pid, realDepositAmount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant{
        harvestFromMasterPark();
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

        IRewarder[] memory _rewarders  = poolInfo[_pid].rewarders;
        for(uint256 i = 0;i < _rewarders.length ; i ++ ){
            IRewarder _rewarder = _rewarders[i];
            if(address(_rewarder) != address(0)){
                _rewarder.onYUZUReward(_pid,msg.sender, user.amount,pending);
            }
        }

        pool.lpToken.safeTransfer(address(msg.sender), _amount);
        emit Withdraw(msg.sender, _pid, _amount);


    }

    function harvestFromMasterPark() public {
        MASTER_PARK.deposit(MASTER_PID, 0);
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
    function getMasterYuzuBetweenBlocks(uint256 _from, uint256 _to) external view returns (uint256 amount ){
        amount = _getMasterYuzuBetweenBlocks(_from,_to);
    }

    //
    function _getMasterYuzuBetweenBlocks(uint256 _from, uint256 _to) internal view returns (uint256 amount ){
        if(_to <= startBlock){
            return 0;
        }else{
            amount = getYuzuBetweenBlocks(_from,_to).mul(MASTER_PARK.poolInfo(MASTER_PID).allocPoint) / MASTER_PARK.totalAllocPoint();
        }
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