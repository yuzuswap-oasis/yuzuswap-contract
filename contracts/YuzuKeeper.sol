// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./YuzuToken.sol";


contract YuzuKeeper is Ownable {
    using SafeMath for uint256;

    struct YuzuApplicatioin {
        address yuzuMember; // Address of member
        uint256 totalValue; // Total yuzu can be request
        uint256 transferedValue; //Total transferd yuzu 
        uint256 perBlockLimit; //  
        uint256 startBlock; // 
    } 


    // The Yuzu TOKEN!
    YuzuToken public yuzu;
    mapping(address => YuzuApplicatioin) public applications;
    bool public appPublished ; //when published ,applications can not be modified
    address public immutable devAddr; //1/4 extra
    address public immutable investorAddr; // 1/8 extra
    address public immutable foundationAddr;// 1/8 extra


    event ApplicationAdded(address indexed yuzuMember, uint256 totalValue,uint256 perBlockLimit, uint256 startBlock );
    event ApplicationPublished(address publisher);

    event YUZUForRequestor(address indexed to ,uint256 amount);

    
    modifier appNotPublished() {
        require(!appPublished, "YuzuSwapMining: app published");
        _;
    }


    constructor(
        YuzuToken _yuzu,
        address _devAddr,
        address _investorAddr,
        address _foundationAddr
    ) public {
        require(_devAddr != address(0));
        require(_investorAddr != address(0));
        require(_foundationAddr != address(0)); 
        require(address(_yuzu) !=  address(0));

        yuzu = _yuzu;
        appPublished = false;
        devAddr = _devAddr;
        investorAddr = _investorAddr;
        foundationAddr = _foundationAddr;
    }


    function addApplication(address _yuzuMember , uint256 _totalValue, uint256 _perBlockLimit,uint256 _startBlock ) public onlyOwner appNotPublished {
        YuzuApplicatioin storage app = applications[_yuzuMember];
        app.yuzuMember = _yuzuMember;
        app.totalValue = _totalValue;
        app.transferedValue = 0;
        app.perBlockLimit = _perBlockLimit;
        app.startBlock = _startBlock;
        emit ApplicationAdded(_yuzuMember,_totalValue,_perBlockLimit,_startBlock);
    
    }

    function publishApplication() public onlyOwner appNotPublished {
        appPublished = true;
        emit ApplicationPublished(msg.sender);
    }
 

    function requestForYUZU(uint256 _amount) public  returns (uint256) {
        // when reward is zero,this should not revert because the swap methods still depend on this
        if(_amount == 0){
            return 0;
        }
        YuzuApplicatioin storage app = applications[msg.sender];
        require( app.yuzuMember == msg.sender  , "not yuzu member"  );
        require(block.number >app.startBlock,"not start");
        uint256 unlocked = block.number.sub(app.startBlock).mul(app.perBlockLimit);
        uint256 newTransferd = app.transferedValue.add(_amount);
        require(newTransferd <=  unlocked, "transferd is over unlocked "); 
        require(newTransferd <= app.totalValue,"transferd is over total ");

        // when 1 yuzu is mint, 0.3 should be sent (0.1 for inverstor,0.1 for foundtaion ,0.1 for dev) 
        //mint to dev,investor,foundation
        yuzu.mint(devAddr,_amount.div(10));
        yuzu.mint(investorAddr,_amount.div(10));
        yuzu.mint(foundationAddr,_amount.div(10));

        uint256 leftAmount = _queryActualYUZUReward(_amount);

        if(!yuzu.mint(msg.sender,leftAmount)){
            //yuzu not enough
            leftAmount = 0;
        }else{ 
            //mint ok
            app.transferedValue = newTransferd;
        }

        emit YUZUForRequestor(msg.sender, leftAmount);
        return leftAmount;
    }

    function queryActualYUZUReward(uint256 _amount) public view returns (uint256) {
        return _queryActualYUZUReward(_amount);
    }

    function _queryActualYUZUReward(uint256 _amount) internal view returns (uint256) {
        uint256 actualAmount =  _amount.div(10).mul(7);
        return actualAmount;
    }
    

}
