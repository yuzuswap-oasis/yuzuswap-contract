import { ethers } from "hardhat";
import { expect } from "chai";

describe("YuzuToken", function () {
  before(async function () {
    this.YuzuToken = await ethers.getContractFactory("YUZUToken")
    this.signers = await ethers.getSigners()
    this.alice = this.signers[0]
    this.bob = this.signers[1]
    this.carol = this.signers[2]
  })

  beforeEach(async function () {
    this.zoo = await this.YuzuToken.deploy()
    await this.zoo.deployed()
  })

  it("should have correct name and symbol and decimal", async function () {
    const name = await this.zoo.name()
    const symbol = await this.zoo.symbol()
    const decimals = await this.zoo.decimals()
    expect(name, "YUZUToken")
    expect(symbol, "YUZU")
    expect(decimals, "18")
  })

  it("should supply token transfers properly", async function () {
    await this.zoo.mint(this.alice.address, "1100")

    await this.zoo.transfer(this.bob.address, "1000")
    await this.zoo.transfer(this.carol.address, "10")
    await this.zoo.connect(this.bob).transfer(this.carol.address, "100", {
      from: this.bob.address,
    })
    const totalSupply = await this.zoo.totalSupply()
    const aliceBal = await this.zoo.balanceOf(this.alice.address)
    const bobBal = await this.zoo.balanceOf(this.bob.address)
    const carolBal = await this.zoo.balanceOf(this.carol.address)
    expect(totalSupply, "1100")
    expect(aliceBal, "90")
    expect(bobBal, "900")
    expect(carolBal, "110")
  })

  it("should fail if you try to do bad transfers", async function () {
    await this.zoo.mint(this.alice.address, "110")
    await this.zoo.transfer(this.bob.address, "100")
    await expect(this.zoo.connect(this.bob).transfer(this.carol.address, "110")).to.be.revertedWith("ERC20: transfer amount exceeds balance")
    await expect(this.zoo.connect(this.carol).transfer(this.carol.address, "1", { from: this.carol.address })).to.be.revertedWith(
      "ERC20: transfer amount exceeds balance"
    )
  })
})
