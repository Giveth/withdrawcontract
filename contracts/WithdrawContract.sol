pragma solidity ^0.4.18;

contract MiniMeToken {
    function balanceOfAt(address _owner, uint _blockNumber) public constant returns (uint);
    function totalSupplyAt(uint _blockNumber) public constant returns(uint);
}

import "../node_modules/giveth-common-contracts/contracts/ERC20.sol";
import "../node_modules/giveth-common-contracts/contracts/Escapable.sol";

contract WithdrawContract is Escapable {
    struct Payment {
        uint block;
        ERC20 token;
        uint amount;
        bool canceled;
    }

    Payment[] public payments;
    MiniMeToken distToken;

    mapping (address => uint) public nextRefundToPay;
    mapping (address => mapping(uint => bool)) skipPayments;

    function WithdrawContract(
        MiniMeToken _distToken,
        address _escapeHatchCaller,
        address _escapeHatchDestination)
        Escapable(_escapeHatchCaller, _escapeHatchDestination) public
    {
        distToken = _distToken;
    }

    function () payable public {
        newEtherPayment(0);
    }

    function newEtherPayment(uint _block) public onlyOwner payable returns (uint idPayment) {
        require(msg.value>0);
        require(_block < block.number);
        idPayment = payments.length ++;
        Payment storage payment = payments[idPayment];
        payment.block = _block == 0 ? block.number -1 : _block;
        payment.token = ERC20(0);
        payment.amount = msg.value;
        NewPayment(idPayment, ERC20(0), msg.value);
    }

    function newTokenPayment(ERC20 token, uint amount, uint _block) public onlyOwner returns (uint idPayment) {
        require(amount > 0);
        require(_block < block.number);
        require( token.transferFrom(msg.sender, address(this), amount) );
        idPayment = payments.length ++;
        Payment storage payment = payments[idPayment];
        payment.block = _block == 0 ? block.number -1 : _block;
        payment.token = token;
        payment.amount = amount;
        NewPayment(idPayment, token, amount);
    }

    function cancelPaymentGlobally(uint idPayment) public onlyOwner {
        require(idPayment < payments.length);
        payments[idPayment].canceled = true;
        CancelPaymentGlobally(idPayment);
    }

    function withdraw() public {
        uint acc = 0;
        ERC20 currentToken = ERC20(0x0);
        uint i = nextRefundToPay[msg.sender];

        require(msg.gas>149000);
        while (( i< payments.length) && ( msg.gas > 148000)) { // TODO Adjust the miminum to a lowe value
            Payment storage payment = payments[i];

            if ((!payment.canceled)&&(!isPaymentSkiped(msg.sender, i))) {
                if (currentToken != payment.token) {
                    nextRefundToPay[msg.sender] = i;
                    require(doPayment(currentToken, msg.sender, acc));
                    Withdraw(i, msg.sender, currentToken, acc);
                    currentToken = payment.token;
                    acc =0;
                }

                acc +=  payment.amount *
                        distToken.balanceOfAt(msg.sender, payment.block) /
                            distToken.totalSupplyAt(payment.block);
            }

            i++;
        }
        nextRefundToPay[msg.sender] = i;
        require(doPayment(currentToken, msg.sender, acc));
        Withdraw(i, msg.sender, currentToken, acc);
    }

    function skipPayment(uint idPayment, bool skip) public {
        require(idPayment < payments.length);
        skipPayments[msg.sender][idPayment] = skip;
    }

    function getPendingReward(ERC20 token, address holder) public constant returns(uint) {
        uint acc =0;
        for (uint i=nextRefundToPay[msg.sender]; i<payments.length; i++) {
            Payment storage payment = payments[i];
            if ((payment.token == token)&&(!payment.canceled) && (!isPaymentSkiped(holder, i))) {
                acc +=  payment.amount *
                    distToken.balanceOfAt(holder, payment.block) /
                        distToken.totalSupplyAt(payment.block);
            }
        }
        return acc;
    }

    function hasFundsAvailable(address holder) constant returns (bool) {
        return nextRefundToPay[holder] < payments.length;
    }

    function nPayments() constant returns (uint) {
        return payments.length;
    }

    function doPayment(ERC20 token, address dest, uint amount) internal returns (bool) {
        if (amount == 0) return true;
        if (address(token) == 0) {
            if (!dest.send(amount)) return false;   // If we can not send, we continue...
        } else {
            if (!token.transfer(dest, amount)) return false;
        }
        return true;
    }

    function getBalance(ERC20 token, address holder) internal constant returns (uint) {
        if (address(token) == 0) {
            return holder.balance;
        } else {
            return token.balanceOf(holder);
        }
    }

    function isPaymentSkiped(address tokenHolder, uint idPayment) constant returns(bool) {
        return skipPayments[tokenHolder][idPayment];
    }

    event Withdraw(uint indexed idPayment, address indexed tokenHolder, ERC20 indexed tokenContract, uint amount);
    event NewPayment(uint indexed idPayment, ERC20 indexed tokenContract, uint amount);
    event CancelPaymentGlobally(uint indexed idPayment);
}
