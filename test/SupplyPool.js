const { BN } = require('openzeppelin-test-helpers');

const SupplyPool = artifacts.require('SupplyPool');
const ERC20Mintable = artifacts.require('ERC20Mintable');
const CDAI = artifacts.require('mocks/CErc20Mock');

const { assertRevert } = require('./helpers/assertThrow');

contract('SupplyPool Test', (accounts) => {
  let supplyPool, totalAllowance;

  const Alice = accounts[0];
  const Bob = accounts[1];
  const Carol = accounts[2];
  const INITIAL_DAI_BALANCE = new BN((100 * 10 ** 18).toString());
  const ZERO = new BN(0);

  beforeEach(async () => {
    dai = await ERC20Mintable.new('DAI Stablecoin', 'dai', 18);
    await dai.mint(Alice, INITIAL_DAI_BALANCE);
    await dai.mint(Bob, INITIAL_DAI_BALANCE);
    await dai.mint(Carol, INITIAL_DAI_BALANCE);
    cdai = await CDAI.new(dai.address, 'Compound DAI', 'cdai', 18);
    supplyPool = await SupplyPool.new(dai.address, cdai.address);
    totalAllowance = await dai.allowance.call(supplyPool.address, cdai.address);
    await dai.approve(supplyPool.address, totalAllowance, { from: Alice });
    await dai.approve(cdai.address, totalAllowance, { from: Alice });
    await dai.approve(supplyPool.address, totalAllowance, { from: Bob });
    await dai.approve(cdai.address, totalAllowance, { from: Bob });
    await dai.approve(supplyPool.address, totalAllowance, { from: Carol });
    await dai.approve(cdai.address, totalAllowance, { from: Carol });
  });

  it('Recognize it\'s a SupplyPool test', async () => {
    const isSupplyPool = await supplyPool.isSupplyPool();
    expect(isSupplyPool).to.be.true;
  });

  it('SupplyPool has allowed DAI', async () => {
    const aliceAllowance = await dai.allowance.call(supplyPool.address, cdai.address);
    aliceAllowance.should.be.bignumber.equal(totalAllowance);
  });

  it('SupplyPool mint', async () => {
    const mintValue = INITIAL_DAI_BALANCE.divRound(new BN(4));
    await supplyPool.mint(mintValue, { from: Alice });

    const accountTokens = await supplyPool.accountTokens.call(Alice);

    const totalEarnings = await supplyPool.getTotalEarning.call();

    totalEarnings.should.be.bignumber.equal(ZERO);
    accountTokens.should.be.bignumber.equal(mintValue);
  });

  it('SupplyPool redeem with profit', async () => {
    const mintValue = INITIAL_DAI_BALANCE.divRound(new BN(4));
    const profit = INITIAL_DAI_BALANCE.divRound(new BN(2));

    await supplyPool.mint(mintValue, { from: Alice });

    await cdai.supplyUnderlying(profit, { from: Carol })

    const balanceOfdaiC = await dai.balanceOf.call(cdai.address);
    balanceOfdaiC.should.be.bignumber.equal(mintValue.add(profit));

    const balanceOfAlice1 = await dai.balanceOf.call(Alice);

    await supplyPool.redeemUnderlying(mintValue, { from: Alice });

    const balanceOfdaiC2 = await dai.balanceOf.call(cdai.address);
    balanceOfdaiC2.should.be.bignumber.equal(profit);

    const totalEarnings = await supplyPool.getTotalEarning.call();

    const accountTokens = await supplyPool.accountTokens.call(Alice);
    const totalTokens = await supplyPool.totalTokens.call();

    const balanceOfAlice2 = await dai.balanceOf.call(Alice);

    const balanceOfdai = await dai.balanceOf.call(supplyPool.address);
    const balanceOfcdai = await cdai.balanceOf.call(supplyPool.address);
    const balanceOfUnderlying = await cdai.balanceOfUnderlying.call(supplyPool.address);

    totalEarnings.should.be.bignumber.equal(profit);
    accountTokens.should.be.bignumber.equal(balanceOfcdai);

    balanceOfAlice1.should.be.bignumber.equal(INITIAL_DAI_BALANCE.sub(mintValue));
    balanceOfAlice2.should.be.bignumber.equal(INITIAL_DAI_BALANCE);

    balanceOfdai.should.be.bignumber.equal(ZERO);
    balanceOfcdai.should.be.bignumber.equal(totalTokens);
    balanceOfUnderlying.should.be.bignumber.equal(totalEarnings);
  });


  it('SupplyPool mint twice', async () => {
    const mintValue = INITIAL_DAI_BALANCE.divRound(new BN(4));

    await supplyPool.mint(mintValue, { from: Alice });
    await supplyPool.mint(mintValue, { from: Alice });

    const accountTokens = await supplyPool.accountTokens.call(Alice);
    const totalEarnings = await supplyPool.getTotalEarning.call();

    totalEarnings.should.be.bignumber.equal(ZERO);
    accountTokens.should.be.bignumber.equal(mintValue.mul(new BN(2)));
  });

  it('SupplyPool mint twice with profit', async () => {
    const mintValue = INITIAL_DAI_BALANCE.divRound(new BN(4));

    await supplyPool.mint(mintValue, { from: Alice });
    await cdai.supplyUnderlying(mintValue, { from: Carol })
    await supplyPool.mint(mintValue, { from: Alice });

    const totalEarnings = await supplyPool.getTotalEarning.call();
    const accountTokens = await supplyPool.accountTokens.call(Alice);

    totalEarnings.should.be.bignumber.equal(mintValue);
    accountTokens.should.be.bignumber.equal(mintValue.div(new BN(2)).mul(new BN(3)));
  });

  it('SupplyPool variable profit', async () => {
    const mintValue = INITIAL_DAI_BALANCE.divRound(new BN(4));
    const profit = new BN(100);

    await supplyPool.mint(mintValue, { from: Alice });
    await cdai.supplyUnderlying(profit, { from: Carol })
    await supplyPool.mint(mintValue, { from: Alice });

    const totalLockedUnderlying = await supplyPool.totalLockedUnderlying.call();
    const balanceOfUnderlying = await cdai.balanceOfUnderlying.call(supplyPool.address);

    balanceOfUnderlying.should.be.bignumber.equal(mintValue.mul(new BN(2)).add(profit));
    totalLockedUnderlying.should.be.bignumber.equal(mintValue.mul(new BN(2)));

    const totalEarnings = await supplyPool.getTotalEarning.call();
    const accountTokens = await supplyPool.accountTokens.call(Alice);

    totalEarnings.should.be.bignumber.equal(profit);
    accountTokens.should.be.bignumber.equal(mintValue.mul(new BN(2)).sub(profit));
  });
});
