
import { ethers } from "hardhat";
import { expect } from "chai";
import { advanceBlockTo ,MAX_UINT256,latest} from "./utilities"
async function getLatestBNumber (){
  return await ethers.provider.getBlockNumber()
}
function floor(n:number){
  return Math.floor(n+0.0000001)
}

describe("YuzuParkExt", function () {
  before(async function () {
    this.signers = await ethers.getSigners()
    this.alice = this.signers[0]
    this.bob = this.signers[1]
    this.carol = this.signers[2]
    this.dev = this.signers[3]
    this.minter = this.signers[4]

    this.ZooPark = await ethers.getContractFactory("YuzuPark")
    this.ZooParkExt = await ethers.getContractFactory("YuzuParkExt")
    this.ZooToken = await ethers.getContractFactory("YUZUToken")
    this.ZooKeeper = await ethers.getContractFactory("YuzuKeeper")
    this.ERC20Mock = await ethers.getContractFactory("ERC20Mock")
    this.StandardReward = await ethers.getContractFactory("StandardReward")

    this.perBlockReward = "1000"
    this.zooKeeperInitBlance = "100000000"


    this.dummyToken = await this.ERC20Mock.deploy("YuzuParkExt", "YPTLP", "10000000000")
    this.tokenUsdt  = await this.ERC20Mock.deploy("USDT", "USDT", "10000000000")
    this.tokenETH  = await this.ERC20Mock.deploy("ETH", "ETH", "10000000000")

    this.zooInst  = await this.ZooToken.deploy()
    this.zooKeeperInst = await this.ZooKeeper.deploy(this.zooInst.address,this.dev.address,this.dev.address,this.dev.address)
    await this.zooInst.transferOwnership(this.zooKeeperInst.address)
  })



  // This hybird test cases should be devided into some specific case
  it("The hybird actions should works well", async function () {
    //Fake init params
    const ZooPerReward = 10000
    const StartBlock = 200 //future block
    const BlockNumberOfHalfAttenuationCycle =  100

    const inst = await this.ZooPark.deploy(this.zooInst.address,this.zooKeeperInst.address,ZooPerReward ,StartBlock,BlockNumberOfHalfAttenuationCycle);
    //add app for zookeeper
    await this.zooKeeperInst.addApplication(
      inst.address,
      StartBlock*ZooPerReward *2,
      ZooPerReward,
      StartBlock,
    )


    //console.log("latest ",await getLatestBNumber())
    await inst.add(50,this.tokenUsdt.address)
    await inst.add(50,this.dummyToken.address)
    const totalPoint = await inst.totalAllocPoint()

    const balance = await this.dummyToken.balanceOf(this.alice.address)

    const instExt = await this.ZooParkExt.deploy(this.zooInst.address,inst.address,this.zooKeeperInst.address,1)
    await this.dummyToken.approve(instExt.address,balance)

    await instExt.init(this.dummyToken.address)

    //add usdt in inst ext without other reward
    //aliace and bob share the lp 
//    console.log("prepare pools")
    await instExt.add(20,this.tokenUsdt.address,[])
    await instExt.add(80,this.tokenETH.address,[])

 //   console.log("prepare token")
    await this.tokenUsdt.transfer(this.bob.address,100)
    await this.tokenETH.transfer(this.bob.address,100)
    //apprve
    await this.tokenUsdt.connect(this.alice).approve(instExt.address,MAX_UINT256,{from:this.alice.address})
    await this.tokenETH.connect(this.alice).approve(instExt.address,MAX_UINT256,{from:this.alice.address})

    await this.tokenUsdt.connect(this.bob).approve(instExt.address,MAX_UINT256,{from:this.bob.address})
    await this.tokenETH.connect(this.bob).approve(instExt.address,MAX_UINT256,{from:this.bob.address})

  //  console.log("deposit")
    //usdt lp
    await instExt.connect(this.alice).deposit(0,10,{from:this.alice.address})
    await instExt.connect(this.bob).deposit(0,40,{from:this.bob.address})
    //eth lp
    await instExt.connect(this.alice).deposit(1,20,{from:this.alice.address})
    await instExt.connect(this.bob).deposit(1,20,{from:this.bob.address})


    /*
    enable when ZooPerReward = 100
    const tables = [
      [0,0],
      [1,100],
      [50,5000],
      [100,10000],
      [101,10050],
      [201,15025],
      [400,18750],
    ]

    console.log("yuzuPerBlock is ",await instExt.yuzuPerBlock())

    for(var i in tables){
      const [block,value] = tables[i]
      expect(await inst.getYuzuFromStartblock(StartBlock,BlockNumberOfHalfAttenuationCycle,ZooPerReward,StartBlock+block) ).to.equal(value);
      expect(await instExt.getYuzuBetweenBlocks(StartBlock,StartBlock+block) ).to.equal(value);
      expect(await instExt.getMasterYuzuBetweenBlocks(StartBlock,StartBlock+block) ).to.equal(Math.floor((value/2)));
    }
    */

    //await for reward start
    const toBlock1 = StartBlock + 11
    await advanceBlockTo(toBlock1.toString())
    console.log("latest ",await getLatestBNumber())

    expect(await instExt.pendingYuzu(0,this.alice.address)).to.equal( Math.floor(   (toBlock1-StartBlock)*ZooPerReward*0.5*0.2*0.2*0.7   ))  
    expect(await instExt.pendingYuzu(0,this.bob.address)).to.equal( Math.floor(   (toBlock1-StartBlock)*ZooPerReward*0.5*0.2*0.8*0.7   ))  

    const aliceBeforeYuzuBal = await this.zooInst.balanceOf(this.alice.address)
    const bobBeforeYuzuBal = await this.zooInst.balanceOf(this.bob.address)

    {
      await instExt.connect(this.alice).withdraw(0,0)
      const currentNo = await getLatestBNumber()
      const aliceAfterYuzuBal = await this.zooInst.balanceOf(this.alice.address)
      expect(aliceAfterYuzuBal - aliceBeforeYuzuBal).to.equal( floor(   (currentNo-StartBlock)*ZooPerReward*0.5*0.2*0.2*0.7   ))  
    }

    {
      await instExt.connect(this.bob).withdraw(0,0)
      const bobAfterYuzuBal = await this.zooInst.balanceOf(this.bob.address)
      const currentNo = await getLatestBNumber()
      console.log("current No is ",currentNo)
      expect(bobAfterYuzuBal - bobBeforeYuzuBal).to.equal( floor(   (currentNo-StartBlock)*ZooPerReward*0.5*0.2*0.8*0.7   ))  
    }
    //Stand reward Use tips:
    //First create contract
    //after add pid, reward start from that blockNumber
    //transfer  tokens
    //YuzuParkExt set pool ,finish binding
    console.log("deploy reward token")
    this.MinterERC20Mock = await ethers.getContractFactory("ERC20Mock",this.minter)
    const rewardToken1  = await this.MinterERC20Mock.deploy("R1", "R1", "10000000000")
    const rewardToken2  = await this.MinterERC20Mock.deploy("R2", "R2", "10000000000")

    const PerBlockTokenAmount = 10000

    const rewardContract1 = await this.StandardReward.deploy(rewardToken1.address,  PerBlockTokenAmount,instExt.address)
    const rewardContract2 = await this.StandardReward.deploy(rewardToken2.address,  PerBlockTokenAmount,instExt.address)

    console.log("init reward contract")
    await rewardContract1.addPool(1,100)
    const reward1StartAt = await getLatestBNumber()

    await rewardContract2.addPool(1,100)
    const reward2StartAt = await getLatestBNumber()

    await rewardContract1.addPool(0,100)
    await rewardContract2.addPool(0,100)
    //first deposit as reward start
    await instExt.set(1,80,[rewardContract1.address,rewardContract2.address],true)
    console.log("alice withdrase")
    await instExt.connect(this.alice).withdraw(1,0)
    console.log("after alice withdrase")
    console.log("bob user info ",await rewardContract1.userInfo(1,this.bob.address) )
    console.log("alice user info ",await rewardContract1.userInfo(1,this.alice.address) )
    console.log("pool  info ",await rewardContract1.poolInfo(1))
    console.log("inst pool  info ",await instExt.poolInfo(1))
    console.log("rewards ",await instExt.poolRewarders(1))

    const alice1StartBlock = (await rewardContract1.poolInfo(1)).lastRewardBlock
    const alice2StartBlock = (await rewardContract2.poolInfo(1)).lastRewardBlock
    expect(alice1StartBlock).to.equal(alice1StartBlock)
    console.log("bob withdrase")
    await instExt.connect(this.bob).withdraw(1,0)
    /*
    console.log("bob user info ",await rewardContract1.userInfo(1,this.bob.address) )
    console.log("alice user info ",await rewardContract1.userInfo(1,this.alice.address) )
    console.log("pool  info ",await rewardContract1.poolInfo(1))
    */
    const bob1StartBlock = (await rewardContract1.poolInfo(1)).lastRewardBlock
    const bob2StartBlock = (await rewardContract2.poolInfo(1)).lastRewardBlock
    expect(bob1StartBlock).to.equal(bob2StartBlock)


    {
      const currentNo = await getLatestBNumber()
      await advanceBlockTo(currentNo+5)
    }
    let currBno = await getLatestBNumber()

    {
      console.log("bob user info ",await rewardContract1.userInfo(1,this.bob.address) )
      console.log("alice user info ",await rewardContract1.userInfo(1,this.alice.address) )
      console.log("pool  info ",await rewardContract1.poolInfo(1))
      const [addr, amount] = await rewardContract1.pendingToken(1,this.bob.address,0)
      expect(addr).to.equal(rewardToken1.address)
      console.log("amount is ",amount, " bob1Start ",bob1StartBlock.valueOf()," aliceStart ",alice1StartBlock.valueOf(), " curr " ,currBno.valueOf())
      expect(amount).to.equal(floor( (currBno-bob1StartBlock) *PerBlockTokenAmount*0.5*0.5     ))
    }

    {
      const [addr, amount] = await rewardContract1.pendingToken(1,this.alice.address,0)
      expect(addr).to.equal(rewardToken1.address)
      console.log("amount is ",amount, " bob1Start ",bob1StartBlock.valueOf()," aliceStart ",alice1StartBlock.valueOf(), " curr " ,currBno.valueOf())
      expect(amount).to.equal(floor(  (currBno- alice1StartBlock) *PerBlockTokenAmount*0.5*0.5   ))
      const {rewardAmounts} = await instExt.pendingTokens(1,this.alice.address)
      expect(amount).to.equal(rewardAmounts[0])
    }

    //transfer reward
    console.log("reward token1 transfer ")
    await rewardToken1.transfer(rewardContract1.address, 10000000)
    await rewardToken2.transfer(rewardContract2.address, 10000000)
    {
      console.log("alice try to withdraw")
      const aliceBeforeRewardToken1Balance = await rewardToken1.balanceOf(this.alice.address)
      await instExt.connect(this.alice).withdraw(1, 0)
      const aliceAfterRewardToken1Balance = await rewardToken1.balanceOf(this.alice.address)

      currBno = await getLatestBNumber()
      expect(aliceAfterRewardToken1Balance - aliceBeforeRewardToken1Balance).to.equal(floor(  (currBno- alice1StartBlock) *PerBlockTokenAmount*0.5*0.5   ))

      console.log("bob try to withdraw")
      const bobBeforeRewardToken1Balance = await  rewardToken1.balanceOf(this.bob.address)
      await instExt.connect(this.bob).withdraw(1, 0)
      currBno = await getLatestBNumber()
      const bobfterRewardToken1Balance = await  rewardToken1.balanceOf(this.bob.address)
      expect(bobfterRewardToken1Balance - bobBeforeRewardToken1Balance).to.equal(floor(  (currBno- bob1StartBlock) *PerBlockTokenAmount*0.5*0.5   ))


    }

})


})
