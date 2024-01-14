// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IMuonClient.sol";

contract DeRandFeeManager is Ownable {
    using SafeERC20 for IERC20;

    struct Executor {
        uint256 id;
        uint256 balance;
        uint256 withdrawnBalance;
    }

    uint256 public lastExecutorId;
    IERC20 public muonToken;

    uint256 public muonAppId;
    IMuonClient.PublicKey public muonPublicKey;
    IMuonClient public muonClient;

    mapping(address => Executor) public executors;
    // cunsumer => ( chainId => ( executor => depositedAmount ) )
    mapping(address => mapping(uint256 => mapping(address => uint256)))
        public deposits;

    event ExecutorAdded(address executor, uint256 id);
    event ExecutorDeposit(
        address depositor,
        address consumer,
        uint256 chainId,
        address executor,
        uint256 amount
    );
    event ExecutorWithdraw(address executor, address recipient, uint256 amount);

    constructor(
        address _muonToken,
        uint256 _muonAppId,
        IMuonClient.PublicKey memory _muonPublicKey,
        address _muonClient
    ) Ownable(msg.sender) {
        muonToken = IERC20(_muonToken);
        muonAppId = _muonAppId;
        muonPublicKey = _muonPublicKey;
        muonClient = IMuonClient(_muonClient);
    }

    function addExecutor(address executor) external returns (uint256) {
        require(executors[executor].id == 0, "Executor already exists");
        lastExecutorId++;
        Executor storage newExecutor = executors[executor];
        newExecutor.id = lastExecutorId;
        return lastExecutorId;
    }

    // TODO: fixme
    function deleteExecutor(address executor) external onlyOwner {}

    function depositForExecutor(
        address _consumer,
        uint256 _chainId,
        address _executor,
        uint256 _amount
    ) external {
        require(executors[_executor].id > 0, "Invalid executor");
        uint256 balance = muonToken.balanceOf(address(this));

        muonToken.safeTransferFrom(msg.sender, address(this), _amount);

        uint256 receivedAmount = muonToken.balanceOf(address(this)) - balance;
        require(_amount == receivedAmount, "Received amount discrepancy");

        deposits[_consumer][_chainId][_executor] += _amount;
        executors[_executor].balance += _amount;

        emit ExecutorDeposit(
            msg.sender,
            _consumer,
            _chainId,
            _executor,
            _amount
        );
    }

    function executorWithdraw(
        address _to,
        uint256 _amount,
        bytes calldata _reqId,
        IMuonClient.SchnorrSign calldata _signature
    ) external {
        Executor storage executor = executors[msg.sender];
        require(executor.id > 0, "Invalid executor");
        require(_amount <= executor.balance, "No enough balance");

        bytes32 hash = keccak256(
            abi.encodePacked(muonAppId, _reqId, msg.sender, _amount)
        );
        verifyMuonSig(_reqId, hash, _signature);

        uint256 withdrawableAmount = _amount - executor.withdrawnBalance;
        executor.withdrawnBalance = _amount;
        muonToken.safeTransfer(_to, withdrawableAmount);

        emit ExecutorWithdraw(msg.sender, _to, _amount);
    }

    function ownerWithdraw(
        address _tokenAddress,
        address _to,
        uint256 _amount
    ) external onlyOwner {
        require(_to != address(0), "Zero address");

        if (_tokenAddress == address(0)) {
            payable(_to).transfer(_amount);
        } else {
            IERC20(_tokenAddress).safeTransfer(_to, _amount);
        }
    }

    function verifyMuonSig(
        bytes calldata reqId,
        bytes32 hash,
        IMuonClient.SchnorrSign calldata sign
    ) internal {
        bool verified = muonClient.muonVerify(
            reqId,
            uint256(hash),
            sign,
            muonPublicKey
        );
        require(verified, "Invalid signature!");
    }
}
