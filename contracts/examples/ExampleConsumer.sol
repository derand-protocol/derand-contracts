// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {DeRandCoordinatorInterface} from "../interfaces/DeRandCoordinatorInterface.sol";
import "../DeRandConsumerBase.sol";

contract ExampleConsumer is DeRandConsumerBase, Ownable {
    uint32 public callbackGasLimit = 100000;
    uint16 public requestConfirmations = 3;
    DeRandCoordinatorInterface public COORDINATOR;

    event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(uint256 requestId, uint256[] randomWords);

    constructor(
        address coordinator
    ) DeRandConsumerBase(coordinator) Ownable(msg.sender) {
        COORDINATOR = DeRandCoordinatorInterface(coordinator);
    }

    function requestRandomWords(
        uint32 numWords
    ) external onlyOwner returns (uint256 requestId) {
        requestId = COORDINATOR.requestRandomWords(
            "",
            0,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );

        emit RequestSent(requestId, numWords);
        return requestId;
    }

    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal override {
        emit RequestFulfilled(requestId, randomWords);
    }
}
