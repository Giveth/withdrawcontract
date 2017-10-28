/* eslint-env mocha */
/* eslint-disable no-await-in-loop */
const TestRPC = require('ethereumjs-testrpc');
const Web3 = require('web3');
const chai = require('chai');
const WithdrawContract = require('../index.js').WithdrawContract;
const MiniMeTokenFactory = require('minimetoken').MiniMeTokenFactory;
const MiniMeToken = require('minimetoken').MiniMeToken;
const MiniMeTokenState = require('minimetoken').MiniMeTokenState;

const assert = chai.assert;

describe('WithdrawContract skip test', () => {
  let testrpc;
  let web3;
  let BN;
  let accounts;
  let withdrawContract;
  let distToken;
  let distTokenState;
  let valueToken;
  let valueTokenState;

  before(async () => {
    testrpc = TestRPC.server({
      ws: true,
      gasLimit: 5800000,
      total_accounts: 10,
    });

    testrpc.listen(8546, '127.0.0.1');

    web3 = new Web3('ws://localhost:8546');
    BN = web3.utils.BN;
    accounts = await web3.eth.getAccounts();
  });

  after((done) => {
    testrpc.close();
    done();
  });

  it('Show pass basic test scenario for skips', async () => {

    const gasPrice = await web3.eth.getGasPrice()

    let acc1balance = await web3.eth.getBalance(accounts[1])
    let acc2balance = await web3.eth.getBalance(accounts[2])
    let acc3balance = await web3.eth.getBalance(accounts[3])

    const tokenFactory = await MiniMeTokenFactory.new(web3);
    const distToken = await MiniMeToken.new(web3,
      tokenFactory.$address,0,0,
      'MiniMe Distribution Token',18,'MDT',true
    );

    const valueToken = await MiniMeToken.new(web3,
      tokenFactory.$address,0,0,
      'valueToken', 18,'TK1',true
    );

    const withdrawContract = await WithdrawContract.new(
      web3,
      distToken.$address,
      accounts[0],
      accounts[0]
    );

    await distToken.generateTokens(accounts[1], 5, { from: accounts[0], gas: 200000 });
    await distToken.generateTokens(accounts[2], 3, { from: accounts[0], gas: 200000 });
    await distToken.generateTokens(accounts[3], 2, { from: accounts[0], gas: 200000 });
    await valueToken.generateTokens(accounts[0], 300);
    
    /// 4 deposits: 1000 wei, 100 TK1, 200 TK1, 2000 wei
    const tx1 = await withdrawContract.newEtherDeposit(0 , { from: accounts[0], value : 1000})
    await valueToken.approve(withdrawContract.$address, 300);
    const tx2 = await withdrawContract.newTokenDeposit(valueToken.$address, 100, 0, { from: accounts[0], gas: 200000 });
    const tx3 = await withdrawContract.newTokenDeposit(valueToken.$address, 200, 0, { from: accounts[0], gas: 200000 });
    const tx4 = await withdrawContract.newEtherDeposit(0 , { from: accounts[0], gas: 200000, value : 2000})

    /// account3 decides to skip the payment of 200TK1
    const tx5 = await withdrawContract.skipPayment(tx3.events.NewDeposit.returnValues.idDeposit,true, { from : accounts[3] })

    /// account1 withdraws all
    const tx6 = await withdrawContract.withdraw({ from: accounts[1], gas: 2000000 });
    assert.equal(await web3.eth.getBalance(accounts[1]), acc1balance-(tx6.gasUsed * gasPrice)+1500);
    assert.equal(await valueToken.balanceOf(accounts[1]), 150);
    acc1balance = await web3.eth.getBalance(accounts[1])

    /// globally cancel 100 TK1 transaction
    await withdrawContract.cancelPaymentGlobally(tx2.events.NewDeposit.returnValues.idDeposit)

    /// account 2 withdraws
    const tx7 = await withdrawContract.withdraw({ from: accounts[2], gas: 2000000 });
    assert.equal(await web3.eth.getBalance(accounts[2]), acc2balance-(tx7.gasUsed * gasPrice)+900);
    assert.equal(await valueToken.balanceOf(accounts[2]), 60);
    acc2balance = await web3.eth.getBalance(accounts[2])

    /// a new diposit of 3000 wei is done
    const tx8 = await withdrawContract.newEtherDeposit(0 , { from: accounts[0], gas: 200000, value : 3000})

    /// account3 withdraws all
    const tx9 = await withdrawContract.withdraw({ from: accounts[3], gas: 2000000 });
    assert.equal(await web3.eth.getBalance(accounts[3]), acc3balance-(tx5.gasUsed+tx9.gasUsed)*gasPrice+1200);
    assert.equal(await valueToken.balanceOf(accounts[3]), 0);

    /// account2 withdraws all
    const tx10 = await withdrawContract.withdraw({ from: accounts[2], gas: 2000000 });
    assert.equal(await web3.eth.getBalance(accounts[2]), acc2balance-tx10.gasUsed*gasPrice+900);

    /// account1 withdraws all
    const tx11 = await withdrawContract.withdraw({ from: accounts[1], gas: 2000000 });
    assert.equal(await web3.eth.getBalance(accounts[1]), acc1balance-tx11.gasUsed*gasPrice+1500);

  }).timeout(20000);

});
