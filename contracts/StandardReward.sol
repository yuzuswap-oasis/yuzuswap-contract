// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./YuzuParkExt.sol";


contract StandardReward is IRewarder,Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

	IERC20 public immutable rewardToken;
	IMasterPark public immutable PARK_EXT ;

	struct UserInfo {
		uint256 amount;
		uint256 rewardDebt;
	}

	struct PoolInfo {
		uint256 accTokenPerShare;
		uint256 lastRewardBlock;
		uint256 allocPoint;
	}

	uint256[] public poolIds;
	/// @notice Info of each pool.
	mapping(uint256 => PoolInfo) public poolInfo;
	/// @notice Info of each user that stakes LP tokens.
	mapping(uint256 => mapping(address => UserInfo)) public userInfo;
	/// @dev Total allocation points. Must be the sum of all allocation points in all pools.
	uint256 public totalAllocPoint;

	uint256 public tokenPerBlock;
	uint256 private constant ACC_TOKEN_PRECISION = 1e12;

	event PoolAdded(uint256 indexed pid, uint256 allocPoint);
	event PoolSet(uint256 indexed pid, uint256 allocPoint);
	event PoolUpdated(uint256 indexed pid, uint256 lastRewardBlock, uint256 lpSupply, uint256 accTokenPerShare);
	event OnReward(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
	event RewardRateUpdated(uint256 oldRate, uint256 newRate);

	modifier onlyExtPark {
		require(msg.sender == address(PARK_EXT), "StandardRewarder::onlyParkExt: only ParkExt can call this function.");
		_;
	}

	constructor(
		IERC20 _rewardToken,
		uint256 _tokenPerBlock,
		IMasterPark _PARK_EXT
	) public {
		require(Address.isContract(address(_rewardToken)), "StandardReward: reward token must be a valid contract");
		require(Address.isContract(address(_PARK_EXT)), "StandardReward: YUZUParkExt  must be a valid contract");

		rewardToken = _rewardToken;
		tokenPerBlock = _tokenPerBlock;
		PARK_EXT = _PARK_EXT;
	}

	/// @notice Add a new LP to the pool. Can only be called by the owner.
	/// DO NOT add the same LP token more than once. Rewards will be messed up if you do.
	/// @param allocPoint AP of the new pool.
	/// @param _pid Pid on MCV2
	function addPool(uint256 _pid, uint256 allocPoint) public onlyOwner {
		require(poolInfo[_pid].lastRewardBlock == 0, "StandardReward::add: cannot add existing pool");

		uint256 lastRewardBlock = block.number;
		totalAllocPoint = totalAllocPoint.add(allocPoint);

		poolInfo[_pid] = PoolInfo({
			allocPoint: allocPoint,
			lastRewardBlock: lastRewardBlock,
			accTokenPerShare: 0
		});
		poolIds.push(_pid);

		emit PoolAdded(_pid, allocPoint);
	}

	/// @notice Update the given pool's SUSHI allocation point and `IRewarder` contract. Can only be called by the owner.
	/// @param _pid The index of the pool. See `poolInfo`.
	/// @param _allocPoint New AP of the pool.
	function setPool(uint256 _pid, uint256 _allocPoint) public onlyOwner {
		totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
		poolInfo[_pid].allocPoint = _allocPoint;

		emit PoolSet(_pid, _allocPoint);
	}

	/// @notice Update reward variables of the given pool.
	/// @param pid The index of the pool. See `poolInfo`.
	/// @return pool Returns the pool that was updated.
	function updatePool(uint256 pid) public returns (PoolInfo memory pool) {
		pool = poolInfo[pid];

		if (block.number > pool.lastRewardBlock) {
			uint256 lpSupply = PARK_EXT.poolInfo(pid).lpToken.balanceOf(address(PARK_EXT));

			if (lpSupply > 0) {
				uint256 blocks = block.number.sub(pool.lastRewardBlock);
				uint256 tokenReward = blocks.mul(tokenPerBlock).mul(pool.allocPoint) / totalAllocPoint;
				pool.accTokenPerShare = pool.accTokenPerShare.add(
					(tokenReward.mul(ACC_TOKEN_PRECISION) / lpSupply)
				);
			}

			pool.lastRewardBlock = block.number;
			poolInfo[pid] = pool;

			emit PoolUpdated(pid, pool.lastRewardBlock, lpSupply, pool.accTokenPerShare);
		}
	}

	/// @notice Update reward variables for all pools
	/// @dev Be careful of gas spending!
	/// @param pids Pool IDs of all to be updated. Make sure to update all active pools.
	function massUpdatePools(uint256[] calldata pids) public {
		uint256 len = pids.length;
		for (uint256 i = 0; i < len; ++i) {
			updatePool(pids[i]);
		}
	}

	/// @dev Sets the distribution reward rate. This will also update all of the pools.
	/// @param _tokenPerBlock The number of tokens to distribute per block
	function setRewardRate(uint256 _tokenPerBlock, uint256[] calldata _pids) external onlyOwner {
		massUpdatePools(_pids);

		uint256 oldRate = tokenPerBlock;
		tokenPerBlock = _tokenPerBlock;

		emit RewardRateUpdated(oldRate, _tokenPerBlock);
	}

	function onYUZUReward(
		uint256 pid,
		address _user,
		uint256 lpToken,
		uint256 _pendingYUZU
	) external override onlyExtPark {
		PoolInfo memory pool = updatePool(pid);
		UserInfo storage user = userInfo[pid][_user];
		uint256 pending;
		// if user had deposited
		if (user.amount > 0) {
			pending = (user.amount.mul(pool.accTokenPerShare) / ACC_TOKEN_PRECISION).sub(user.rewardDebt);
			rewardToken.safeTransfer(_user, pending);
		}

		user.amount = lpToken;
	    user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(ACC_TOKEN_PRECISION);


		emit OnReward(_user, pid, pending,_user );
	}

	/// @notice View function to see pending Token
	/// @param _pid The index of the pool. See `poolInfo`.
	/// @param _user Address of user.
	/// @return token  reward addr for a given user.
	/// @return pending reward amount for a given user.
	function pendingToken(uint256 _pid, address _user,uint256 _pendingYUZU) external view override returns (IERC20 token,uint256 pending) {
		PoolInfo memory pool = poolInfo[_pid];
		UserInfo storage user = userInfo[_pid][_user];

		uint256 accTokenPerShare = pool.accTokenPerShare;
		uint256 lpSupply = PARK_EXT.poolInfo(_pid).lpToken.balanceOf(address(PARK_EXT));

		if (block.number > pool.lastRewardBlock && lpSupply != 0) {
			uint256 blocks = block.number.sub(pool.lastRewardBlock);
			uint256 tokenReward = blocks.mul(tokenPerBlock).mul(pool.allocPoint) / totalAllocPoint;
			accTokenPerShare = accTokenPerShare.add(tokenReward.mul(ACC_TOKEN_PRECISION) / lpSupply);
		}

		token = rewardToken;
		pending = (user.amount.mul(accTokenPerShare) / ACC_TOKEN_PRECISION).sub(user.rewardDebt);
	}
}