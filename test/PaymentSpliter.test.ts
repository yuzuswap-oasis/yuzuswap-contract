import { ethers } from "hardhat";
import { expect } from "chai";

describe("YuzuToken", function () {
  before(async function () {
    this.signers = await ethers.getSigners()
    this.alice = this.signers[0]
    this.bob = this.signers[1]
    this.carol = this.signers[2]
    this.ERC20Mock = await ethers.getContractFactory("ERC20Mock")
    this.PaymentSpliter = await ethers.getContractFactory("PaymentSplitterV2")
  })

  beforeEach(async function () {

    this.tokenUsdt  = await this.ERC20Mock.deploy("USDT", "USDT", "10000000000")
    this.tokenETH  = await this.ERC20Mock.deploy("ETH", "ETH", "10000000000")
    this.psIns = await this.PaymentSpliter.deploy([this.bob.address,this.carol.address],[80,20])
  })

  it("should works ok fo spliter basic functions", async function () {
    await this.tokenUsdt.transfer(this.psIns.address, 1000)
    await this.tokenETH.transfer(this.psIns.address, 2000)

    await this.psIns.connect(this.bob)["release(address,address)"](this.tokenUsdt.address,this.bob.address)
    expect(await this.tokenUsdt.balanceOf(this.bob.address)).to.equal(1000 * 80/100 )

    await this.psIns.connect(this.carol)["release(address,address)"](this.tokenETH.address,this.carol.address)
    expect(await this.tokenETH.balanceOf(this.carol.address)).to.equal(2000 * 20/100 )

    await this.psIns.connect(this.bob)["release(address,address)"](this.tokenETH.address,this.bob.address)
    expect(await this.tokenETH.balanceOf(this.bob.address)).to.equal(2000 * 80/100 )


  })
})
