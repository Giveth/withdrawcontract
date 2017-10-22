const WithdrawContractAbi = require('../build/WithdrawContract.sol').WithdrawContractAbi;
const WithdrawContractByteCode = require('../build/WithdrawContract.sol').WithdrawContractByteCode;
const generateClass = require('eth-contract-class').default;

module.exports = generateClass(WithdrawContractAbi, WithdrawContractByteCode);
