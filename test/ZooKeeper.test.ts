
import { ethers } from "hardhat";
import { expect } from "chai";
import { advanceBlockTo,getBigNumber } from "./utilities"

describe("YuzuKeeper", function () {
  before(async function () {
    this.signers = await ethers.getSigners()
    this.alice = this.signers[0]
    this.bob = this.signers[1]
    this.carol = this.signers[2]
    this.dev = this.signers[3]
    this.minter = this.signers[4]

    this.ZooKeeper = await ethers.getContractFactory("YuzuKeeper")
    this.ZooToken = await ethers.getContractFactory("YUZUToken")
  })

  beforeEach(async function () {
    this.zoo = await this.ZooToken.deploy()
    await this.zoo.deployed()

    this.zookeeper = await this.ZooKeeper.deploy(this.zoo.address,this.alice.address,this.carol.address,this.bob.address)
    await this.zookeeper.deployed()
    await this.zoo.transferOwnership(this.zookeeper.address)
  })

  it("zookeeper support transfer owner", async function () {
    await this.zookeeper.transferOwnership(this.bob.address);
    const owner = await this.zookeeper.owner()
    expect(owner).to.equal(this.bob.address)
  })


  it("zookeeper fetch applycation info  success", async function () {
    let memberAddr = this.dev.address;
    let totalValue = "100"
    let perBlockLimit = "10"
    let startBlock = "10";
    await this.zookeeper.addApplication(memberAddr,totalValue,perBlockLimit,startBlock) 

    let app = await this.zookeeper.applications(memberAddr);
    expect(app.yuzuMember).to.equal(memberAddr);
    expect(app.totalValue).to.equal(totalValue);
    expect(app.transferedValue).to.equal(0);
    expect(app.perBlockLimit).to.equal(perBlockLimit);
    expect(app.startBlock).to.equal(startBlock);

  })

  it("zookeeper add applications  success", async function () {
    let memberAddr = this.dev.address;
    let totalValue = "100"
    let perBlockLimit = "10"
    let startBlock = "80";
    await this.zookeeper.addApplication(memberAddr,totalValue,perBlockLimit,startBlock) ;
    expect(await this.zoo.balanceOf(this.zookeeper.address)).to.equal("0");
    expect(await this.zoo.balanceOf(memberAddr)).to.equal("0");

    await expect(this.zookeeper.connect(this.bob).requestForYUZU(100,{from: this.bob.address})).to.be.revertedWith("not yuzu member"); 

    await advanceBlockTo("79")
    await expect(this.zookeeper.connect(this.dev).requestForYUZU(100,{from: memberAddr})).to.be.revertedWith("not start"); //block 80
    await this.zookeeper.connect(this.dev).requestForYUZU(10);
    await expect(this.zookeeper.connect(this.dev).requestForYUZU(11,{from: memberAddr})).to.be.revertedWith("transferd is over unlocked "); //block 81

    await advanceBlockTo("100")

    await expect(this.zookeeper.connect(this.dev).requestForYUZU(91,{from: memberAddr})).to.be.revertedWith("transferd is over total "); //block 101
    await this.zookeeper.connect(this.dev).requestForYUZU(90,{from: memberAddr})

    expect(await this.zoo.balanceOf(memberAddr)).to.equal(100 * 0.7);
    await expect(this.zookeeper.connect(this.dev).requestForYUZU(10,{from: memberAddr})).to.be.revertedWith("transferd is over total")


  })
})
