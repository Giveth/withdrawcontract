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

describe('LiquidPledging test', () => {
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

  it('Should deploy the distribution token contract', async () => {
    const tokenFactory = await MiniMeTokenFactory.new(web3);
    distToken = await MiniMeToken.new(web3,
      tokenFactory.$address,
      0,
      0,
      'MiniMe Distribution Token',
      18,
      'MDT',
      true);
    assert.ok(distToken.$address);
    distTokenState = new MiniMeTokenState(distToken);
  }).timeout(20000);
  it('Should create distribution tokens', async () => {
    await distToken.generateTokens(accounts[1], 5, { from: accounts[0], gas: 200000 });
    await distToken.generateTokens(accounts[2], 3, { from: accounts[0], gas: 200000 });
    await distToken.generateTokens(accounts[3], 2, { from: accounts[0], gas: 200000 });
    const st = await distTokenState.getState();
    assert.equal(st.balances[accounts[1]], 5);
    assert.equal(st.balances[accounts[2]], 3);
    assert.equal(st.balances[accounts[3]], 2);
    assert.equal(st.totalSupply, 10);
  }).timeout(6000);
  it('Should deploy a value token', async () => {
    const tokenFactory = await MiniMeTokenFactory.new(web3);
    valueToken = await MiniMeToken.new(web3,
      tokenFactory.$address,
      0,
      0,
      'MiniMe Value Token',
      18,
      'MVT',
      true);
    assert.ok(distToken.$address);
    valueTokenState = new MiniMeTokenState(valueToken);
  }).timeout(20000);
  it('Should create value tokens', async () => {
    await valueToken.generateTokens(accounts[0], 100, { from: accounts[0], gas: 200000 });
    const st = await valueTokenState.getState();
    assert.equal(st.balances[accounts[0]], 100);
    assert.equal(st.totalSupply, 100);
  });
  it('Should deploy the withdraw contract', async () => {
    withdrawContract = await WithdrawContract.new(web3, distToken.$address);
    assert.ok(withdrawContract.$address);
  });
  it('Should pop with ether', async () => {
    await web3.eth.sendTransaction({
      from: accounts[0],
      value: 100,
      to: withdrawContract.$address });
    const nPayments = await withdrawContract.nPayments();
    assert.equal(nPayments, 1);
    const v = await web3.eth.getBalance(withdrawContract.$address);
    assert.equal(v, 100);
  });
  it('Should pop with value token', async () => {
    await valueToken.approve(withdrawContract.$address, 100);
    await withdrawContract.newTokenPayment(valueToken.$address, 100, 0);
    const balance = await valueToken.balanceOf(withdrawContract.$address);
    assert.equal(balance, 100);
  });
  it('Should withdraw values', async () => {
    const oldValues = [];
    oldValues[1] = new BN(await web3.eth.getBalance(accounts[1]));
    oldValues[2] = new BN(await web3.eth.getBalance(accounts[2]));
    oldValues[3] = new BN(await web3.eth.getBalance(accounts[3]));
    const txs = [];
    txs[1] = await withdrawContract.withdraw({ from: accounts[1], gas: 300000 });
    txs[2] = await withdrawContract.withdraw({ from: accounts[2], gas: 300000 });
    txs[3] = await withdrawContract.withdraw({ from: accounts[3], gas: 300000 });
    const st = await valueTokenState.getState();
    assert.equal(st.balances[accounts[1]], 50);
    assert.equal(st.balances[accounts[2]], 30);
    assert.equal(st.balances[accounts[3]], 20);
    const newValues = [];
    newValues[1] = new BN(await web3.eth.getBalance(accounts[1]));
    newValues[2] = new BN(await web3.eth.getBalance(accounts[2]));
    newValues[3] = new BN(await web3.eth.getBalance(accounts[3]));

    const gasPrice = new BN(await web3.eth.getGasPrice());
    const d = [];
//    d[1] = newValues[1].sub(oldValues[1]).add(gasPrice.mul(txs[1].gasUsed));
    d[1] = newValues[1].sub(oldValues[1]).add(new BN(txs[1].gasUsed).mul(gasPrice));
    d[2] = newValues[2].sub(oldValues[2]).add(new BN(txs[2].gasUsed).mul(gasPrice));
    d[3] = newValues[3].sub(oldValues[3]).add(new BN(txs[3].gasUsed).mul(gasPrice));

    assert.equal(d[1], 50);
    assert.equal(d[2], 30);
    assert.equal(d[3], 20);
  });
});
